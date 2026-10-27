import io
import os
import sqlite3
import h5py
import numpy as np
from PIL import Image
from fastapi import FastAPI, UploadFile, File
from fastapi.middleware.cors import CORSMiddleware

import tensorflow as tf
import keras
import tf_keras
import tensorflow_hub as hub

app = FastAPI(title="ASD-Sense Inference API", version="2.0")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

DB_PATH = "asd_sense.db"
SCHEMA_PATH = "asd_sense_database_schema.sql"

# Model file paths in backend/models/
GESTURE_MOBILENET_PATH = "models/best_gesture_mobilenet.keras"
GESTURE_VIT_WEIGHTS_PATH = "models/best_gesture_vit.weights.h5"

FACIAL_MOBILENET_PATH = "models/best_facial_mobilenet.keras"
FACIAL_VIT_WEIGHTS_PATH = "models/best_facial_vit.weights.h5"

VIT_HUB_URL = "https://tfhub.dev/sayakpaul/vit_b16_fe/1"

IMG_SIZE = (224, 224)
EDGE_CONFIDENCE_THRESHOLD = 0.85  # Escalate to Cloud ViT if MobileNet confidence < 85%
INCONCLUSIVE_THRESHOLD = 0.60

gesture_mobilenet = None
gesture_vit = None
facial_mobilenet = None
facial_vit = None


def init_db():
    if not os.path.exists(SCHEMA_PATH):
        print(f"WARNING: Database schema not found at {SCHEMA_PATH}")
        return
    with sqlite3.connect(DB_PATH) as conn:
        with open(SCHEMA_PATH, "r", encoding="utf-8") as f:
            conn.executescript(f.read())
        cursor = conn.cursor()
        cursor.execute(
            """
            INSERT OR IGNORE INTO Users (user_id, full_name, email, password_hash, role)
            VALUES (1, 'Test Guardian', 'guardian@asdsense.com', 'hashed_pw', 'guardian')
            """
        )
        cursor.execute(
            """
            INSERT OR IGNORE INTO Child_Profiles (child_id, user_id, first_name, date_of_birth)
            VALUES (1, 1, 'Test Child', '2021-05-15')
            """
        )
        conn.commit()
    print("SQLite database initialized successfully.")


def build_gesture_vit():
    """Matches Model_ViT.ipynb (Hand Gestures) architecture."""
    vit_layer = hub.KerasLayer(VIT_HUB_URL, trainable=True, name="vit_layer")
    model = tf_keras.Sequential([
        tf_keras.layers.Input(shape=(224, 224, 3)),
        tf_keras.layers.RandomFlip("horizontal"),
        tf_keras.layers.RandomRotation(0.1),
        vit_layer,
        tf_keras.layers.BatchNormalization(),
        tf_keras.layers.Dense(128, activation="relu"),
        tf_keras.layers.Dropout(0.5),
        tf_keras.layers.Dense(1, activation="sigmoid"),
    ])
    return model


def build_facial_vit():
    """Matches Block 11 of the Facial ViT-B/16 notebook architecture."""
    vit_augmentation = tf_keras.Sequential(
        [
            tf_keras.layers.RandomFlip("horizontal"),
            tf_keras.layers.RandomRotation(0.03, fill_mode="nearest"),
            tf_keras.layers.RandomZoom(0.10, fill_mode="nearest"),
            tf_keras.layers.RandomTranslation(0.05, 0.05, fill_mode="nearest"),
            tf_keras.layers.RandomBrightness(0.15, value_range=(0, 255)),
            tf_keras.layers.RandomContrast(0.15),
        ],
        name="vit_facial_augmentation",
    )
    vit_layer = hub.KerasLayer(VIT_HUB_URL, trainable=True, name="vit_layer")
    model = tf_keras.Sequential(
        [
            tf_keras.layers.Input(shape=(224, 224, 3)),
            vit_augmentation,
            tf_keras.layers.Rescaling(1.0 / 127.5, offset=-1),
            vit_layer,
            tf_keras.layers.BatchNormalization(),
            tf_keras.layers.Dense(128, activation="relu"),
            tf_keras.layers.Dropout(0.5),
            tf_keras.layers.Dense(1, activation="sigmoid"),
        ],
        name="ASD_Sense_ViT_B16",
    )
    return model


def _collect_ordered_h5_arrays(group):
    """Recursively extracts HDF5 dataset arrays sorted numerically by key ('0', '1', ..., '197')."""
    arrays = []
    keys = sorted(group.keys(), key=lambda k: (0, int(k)) if k.isdigit() else (1, k))
    for k in keys:
        if k == "optimizer":
            continue
        item = group[k]
        if isinstance(item, h5py.Dataset):
            arrays.append(item[()])
        elif isinstance(item, h5py.Group):
            arrays.extend(_collect_ordered_h5_arrays(item))
    return arrays


def load_vit_weights_safely(model, h5_path: str):
    """Loads classification head and nested TF Hub ViT weights without failing on empty top-level vars."""
    # Step 1: Load head layers (BatchNorm, Dense) and child trackables with skip_mismatch=True
    model.load_weights(h5_path, skip_mismatch=True)

    # Step 2: Match and assign the 198 ViT backbone tensors if stored in nested H5 subgroups
    vit_layer = model.get_layer("vit_layer")
    vit_vars = vit_layer.weights
    if not vit_vars:
        return

    with h5py.File(h5_path, "r") as f:
        root_group = f.get("layers", f)
        all_arrays = _collect_ordered_h5_arrays(root_group)

        target_shapes = [tuple(v.shape) for v in vit_vars]
        n = len(target_shapes)
        for start_idx in range(len(all_arrays) - n + 1):
            candidate = [arr.shape for arr in all_arrays[start_idx : start_idx + n]]
            if candidate == target_shapes:
                for v, arr in zip(vit_vars, all_arrays[start_idx : start_idx + n]):
                    v.assign(arr)
                print(f"Assigned {n} fine-tuned ViT backbone tensors from {h5_path}")
                break


@app.on_event("startup")
def startup_event():
    global gesture_mobilenet, gesture_vit, facial_mobilenet, facial_vit
    init_db()

    # 1. Load Hand Gesture MobileNetV2
    if os.path.exists(GESTURE_MOBILENET_PATH):
        try:
            gesture_mobilenet = keras.models.load_model(GESTURE_MOBILENET_PATH, compile=False)
            print(f"Loaded Gesture MobileNetV2 from {GESTURE_MOBILENET_PATH}")
        except Exception:
            try:
                gesture_mobilenet = tf_keras.models.load_model(GESTURE_MOBILENET_PATH, compile=False)
                print(f"Loaded Gesture MobileNetV2 (tf_keras) from {GESTURE_MOBILENET_PATH}")
            except Exception as e:
                print(f"WARNING: Failed to load Gesture MobileNetV2: {e}")
    else:
        print(f"INFO: Gesture MobileNetV2 not found at {GESTURE_MOBILENET_PATH}")

    # 2. Load Hand Gesture ViT-B/16
    if os.path.exists(GESTURE_VIT_WEIGHTS_PATH):
        try:
            gesture_vit = build_gesture_vit()
            load_vit_weights_safely(gesture_vit, GESTURE_VIT_WEIGHTS_PATH)
            print(f"Loaded Gesture ViT-B/16 from {GESTURE_VIT_WEIGHTS_PATH}")
        except Exception as e:
            print(f"WARNING: Failed to load Gesture ViT-B/16: {e}")
    else:
        print(f"INFO: Gesture ViT weights not found at {GESTURE_VIT_WEIGHTS_PATH}")

    # 3. Load Facial MobileNetV2
    if os.path.exists(FACIAL_MOBILENET_PATH):
        try:
            facial_mobilenet = tf_keras.models.load_model(FACIAL_MOBILENET_PATH, compile=False)
            print(f"Loaded Facial MobileNetV2 from {FACIAL_MOBILENET_PATH}")
        except Exception:
            try:
                facial_mobilenet = keras.models.load_model(FACIAL_MOBILENET_PATH, compile=False)
                print(f"Loaded Facial MobileNetV2 (keras) from {FACIAL_MOBILENET_PATH}")
            except Exception as e:
                print(f"WARNING: Failed to load Facial MobileNetV2: {e}")
    else:
        print(f"INFO: Facial MobileNetV2 not found at {FACIAL_MOBILENET_PATH}")

    # 4. Load Facial ViT-B/16
    if os.path.exists(FACIAL_VIT_WEIGHTS_PATH):
        try:
            facial_vit = build_facial_vit()
            load_vit_weights_safely(facial_vit, FACIAL_VIT_WEIGHTS_PATH)
            print(f"Loaded Facial ViT-B/16 from {FACIAL_VIT_WEIGHTS_PATH}")
        except Exception as e:
            print(f"WARNING: Failed to load Facial ViT-B/16: {e}")
    else:
        print(f"INFO: Facial ViT weights not found at {FACIAL_VIT_WEIGHTS_PATH}")


def preprocess_raw_255(image_bytes: bytes) -> np.ndarray:
    """Used for Gesture MobileNet, Facial MobileNet, and Facial ViT (internal rescaling)."""
    image = Image.open(io.BytesIO(image_bytes)).convert("RGB").resize(IMG_SIZE)
    img_array = np.asarray(image, dtype=np.float32)
    return np.expand_dims(img_array, axis=0)


def preprocess_external_vit(image_bytes: bytes) -> np.ndarray:
    """Used only for Gesture ViT, which scales pixels to [-1, 1] outside the model."""
    image = Image.open(io.BytesIO(image_bytes)).convert("RGB").resize(IMG_SIZE)
    img_array = (np.asarray(image, dtype=np.float32) / 127.5) - 1.0
    return np.expand_dims(img_array, axis=0)


def log_screening_to_db(
    child_id: int,
    model_used: str,
    predicted_class: str,
    prob_autistic: float,
    confidence: float,
    filename: str,
    routing_tier: str,
) -> int:
    with sqlite3.connect(DB_PATH) as conn:
        cursor = conn.cursor()
        cursor.execute(
            """
            INSERT INTO Screening_Records (
                child_id, performed_by_user_id, model_name, model_version,
                predicted_class, autism_probability, confidence, image_reference, notes
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
            """,
            (
                child_id,
                1,
                model_used,
                "1.0",
                predicted_class,
                round(prob_autistic, 4),
                round(confidence, 4),
                filename,
                routing_tier,
            ),
        )
        screening_id = cursor.lastrowid
        conn.commit()
    return screening_id


@app.get("/")
def read_root():
    return {
        "status": "ASD-Sense Backend Online",
        "gesture_mobilenet_loaded": gesture_mobilenet is not None,
        "gesture_vit_loaded": gesture_vit is not None,
        "facial_mobilenet_loaded": facial_mobilenet is not None,
        "facial_vit_loaded": facial_vit is not None,
    }


@app.post("/predict/gesture")
async def analyze_gesture(file: UploadFile = File(...), child_id: int = 1):
    image_bytes = await file.read()
    model_used = "Gesture_MobileNetV2"
    routing_tier = "Edge / API screening"

    if gesture_mobilenet is None and gesture_vit is None:
        _ = preprocess_raw_255(image_bytes)
        prob_autistic = 0.8850
        confidence = 0.8850
        model_used = "Simulated_Gesture_Model"
        routing_tier = "Test mode (awaiting gesture model weights)"
    elif gesture_mobilenet is not None:
        raw_input = preprocess_raw_255(image_bytes)
        prob_autistic = float(gesture_mobilenet.predict(raw_input, verbose=0)[0][0])
        confidence = max(prob_autistic, 1.0 - prob_autistic)

        if confidence < EDGE_CONFIDENCE_THRESHOLD and gesture_vit is not None:
            vit_input = preprocess_external_vit(image_bytes)
            prob_autistic = float(gesture_vit.predict(vit_input, verbose=0)[0][0])
            confidence = max(prob_autistic, 1.0 - prob_autistic)
            model_used = "Gesture_ViT-B16"
            routing_tier = "Cloud clinical diagnosis (escalated)"
    else:
        vit_input = preprocess_external_vit(image_bytes)
        prob_autistic = float(gesture_vit.predict(vit_input, verbose=0)[0][0])
        confidence = max(prob_autistic, 1.0 - prob_autistic)
        model_used = "Gesture_ViT-B16"
        routing_tier = "Cloud clinical diagnosis"

    if confidence < INCONCLUSIVE_THRESHOLD:
        predicted_class = "inconclusive"
    elif prob_autistic >= 0.5:
        predicted_class = "autistic"
    else:
        predicted_class = "non_autistic"

    screening_id = log_screening_to_db(
        child_id, model_used, predicted_class, prob_autistic, confidence, file.filename, routing_tier
    )

    return {
        "screening_id": screening_id,
        "filename": file.filename,
        "model_name": model_used,
        "routing": routing_tier,
        "predicted_class": predicted_class,
        "autism_probability": round(prob_autistic, 4),
        "confidence": round(confidence, 4),
    }


@app.post("/predict/facial")
async def analyze_facial(file: UploadFile = File(...), child_id: int = 1):
    image_bytes = await file.read()
    raw_input = preprocess_raw_255(image_bytes)
    model_used = "Facial_MobileNetV2"
    routing_tier = "Edge / API screening"

    if facial_mobilenet is None and facial_vit is None:
        prob_autistic = 0.8600
        confidence = 0.8600
        model_used = "Simulated_Facial_Model"
        routing_tier = "Test mode (awaiting facial model weights)"
    elif facial_mobilenet is not None:
        prob_autistic = float(facial_mobilenet.predict(raw_input, verbose=0)[0][0])
        confidence = max(prob_autistic, 1.0 - prob_autistic)

        if confidence < EDGE_CONFIDENCE_THRESHOLD and facial_vit is not None:
            prob_autistic = float(facial_vit.predict(raw_input, verbose=0)[0][0])
            confidence = max(prob_autistic, 1.0 - prob_autistic)
            model_used = "Facial_ViT-B16"
            routing_tier = "Cloud clinical diagnosis (escalated)"
    else:
        prob_autistic = float(facial_vit.predict(raw_input, verbose=0)[0][0])
        confidence = max(prob_autistic, 1.0 - prob_autistic)
        model_used = "Facial_ViT-B16"
        routing_tier = "Cloud clinical diagnosis"

    if confidence < INCONCLUSIVE_THRESHOLD:
        predicted_class = "inconclusive"
    elif prob_autistic >= 0.5:
        predicted_class = "autistic"
    else:
        predicted_class = "non_autistic"

    screening_id = log_screening_to_db(
        child_id, model_used, predicted_class, prob_autistic, confidence, file.filename, routing_tier
    )

    return {
        "screening_id": screening_id,
        "filename": file.filename,
        "model_name": model_used,
        "routing": routing_tier,
        "predicted_class": predicted_class,
        "autism_probability": round(prob_autistic, 4),
        "confidence": round(confidence, 4),
    }


@app.get("/records/screenings")
def get_screenings(child_id: int = 1):
    with sqlite3.connect(DB_PATH) as conn:
        conn.row_factory = sqlite3.Row
        cursor = conn.cursor()
        cursor.execute(
            "SELECT * FROM Screening_Records WHERE child_id = ? ORDER BY screening_date DESC",
            (child_id,),
        )
        rows = [dict(row) for row in cursor.fetchall()]
    return {"child_id": child_id, "screenings": rows}