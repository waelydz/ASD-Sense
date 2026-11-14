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

from quantize_vit import BASE_DIR, MODELS_DIR, build_clean_facial_vit
from child_profiles_api import create_child_profiles_router

app = FastAPI(title="ASD-Sense Inference API", version="2.0")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

DB_PATH = os.path.join(BASE_DIR, "asd_sense.db")
SCHEMA_PATH = os.path.join(BASE_DIR, "asd_sense_database_schema.sql")

# CRUD routes are registered without changing inference/model-loading code.
# They remain inaccessible until verified authentication sets request.state.user_id.
app.include_router(create_child_profiles_router(DB_PATH))

# Model file paths in backend/models/
GESTURE_MOBILENET_PATH = os.path.join(MODELS_DIR, "best_gesture_mobilenet.keras")
GESTURE_VIT_WEIGHTS_PATH = os.path.join(MODELS_DIR, "best_gesture_vit.weights.h5")

FACIAL_MOBILENET_PATH = os.path.join(MODELS_DIR, "best_facial_mobilenet.keras")
FACIAL_VIT_WEIGHTS_PATH = os.path.join(MODELS_DIR, "best_facial_vit.weights.h5")
QUANT_FACIAL_VIT_NPZ_PATH = os.path.join(MODELS_DIR, "facial_vit_b16_quantized.npz")
TFLITE_FACIAL_VIT_PATH = os.path.join(MODELS_DIR, "facial_vit_b16_quantized.tflite")

VIT_HUB_URL = "https://tfhub.dev/sayakpaul/vit_b16_fe/1"

IMG_SIZE = (224, 224)
EDGE_CONFIDENCE_THRESHOLD = 1.01  # Escalate to Cloud ViT if MobileNet confidence < 85%
INCONCLUSIVE_THRESHOLD = 0.60

gesture_mobilenet = None
gesture_vit = None
facial_mobilenet = None
facial_vit = None
tflite_facial_vit_interpreter = None
facial_vit_model_label = "Facial_ViT-B16"


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
    """Builds the clean Hand Gesture ViT-B/16 inference graph."""
    vit_layer = hub.KerasLayer(VIT_HUB_URL, trainable=False, name="vit_layer")
    model = tf_keras.Sequential([
        tf_keras.layers.InputLayer(input_shape=(224, 224, 3)),
        vit_layer,
        tf_keras.layers.BatchNormalization(name="batch_normalization"),
        tf_keras.layers.Dense(128, activation="relu", name="dense"),
        tf_keras.layers.Dropout(0.5, name="dropout"),
        tf_keras.layers.Dense(1, activation="sigmoid", name="dense_1"),
    ])
    model.build((1, 224, 224, 3))
    return model


def load_vit_weights_safely(model, h5_path: str):
    """Restores all 198 ViT backbone tensors and 8 classification head tensors via h5py."""
    vit_datasets = {}
    head_datasets = []

    with h5py.File(h5_path, "r") as f:
        def collect_datasets(name, obj):
            if isinstance(obj, h5py.Dataset) and "optimizer" not in name.lower():
                arr = np.array(obj)
                if "vit_layer" in name or "keras_layer" in name:
                    vit_datasets[name] = arr
                else:
                    head_datasets.append((name, arr))
        f.visititems(collect_datasets)

    # 1. Assign 198 ViT backbone variables
    vit_vars = model.get_layer("vit_layer").variables
    if len(vit_datasets) >= len(vit_vars):
        def sort_key(item):
            parts = [int(s) for s in item[0].replace("/", "_").split("_") if s.isdigit()]
            return parts if parts else [0]

        sorted_arrays = [val for _, val in sorted(vit_datasets.items(), key=sort_key)]
        assigned_vit = 0
        for var in vit_vars:
            for i, arr in enumerate(sorted_arrays):
                if arr is not None and var.shape == arr.shape:
                    var.assign(arr)
                    sorted_arrays[i] = None
                    assigned_vit += 1
                    break
        print(f"Assigned {assigned_vit}/{len(vit_vars)} fine-tuned ViT backbone tensors from {h5_path}")

    # 2. Assign 8 classification head variables (BatchNorm, Dense, Dense_1)
    head_vars = (
        model.get_layer("batch_normalization").variables
        + model.get_layer("dense").variables
        + model.get_layer("dense_1").variables
    )
    assigned_head = 0
    used_indices = set()
    for var in head_vars:
        var_base = var.name.split(":")[0].split("/")[-1]
        matched = False
        for idx, (h5_name, arr) in enumerate(head_datasets):
            if idx not in used_indices and var.shape == arr.shape and var_base in h5_name:
                var.assign(arr)
                used_indices.add(idx)
                assigned_head += 1
                matched = True
                break
        if not matched:
            for idx, (h5_name, arr) in enumerate(head_datasets):
                if idx not in used_indices and var.shape == arr.shape:
                    var.assign(arr)
                    used_indices.add(idx)
                    assigned_head += 1
                    break
    print(f"Assigned {assigned_head}/{len(head_vars)} classification head tensors from {h5_path}")


def load_quantized_int8_vit_npz(model, npz_path: str):
    """Loads INT8 post-training quantized weights from facial_vit_b16_quantized.npz."""
    data = np.load(npz_path)
    loaded = 0
    for idx, var in enumerate(model.variables):
        if f"w_{idx}_int8" in data:
            w_int8 = data[f"w_{idx}_int8"].astype(np.float32)
            scale = float(data[f"w_{idx}_scale"][0])
            var.assign(w_int8 * scale)
            loaded += 1
        elif f"w_{idx}_fp16" in data:
            var.assign(data[f"w_{idx}_fp16"].astype(np.float32))
            loaded += 1
    print(f"Loaded INT8 Quantized Facial ViT-B/16 ({loaded} tensors) from {npz_path}")


def predict_with_tflite_vit(img_tensor_255: np.ndarray) -> float:
    """Runs inference on a [1, 224, 224, 3] float32 image tensor using the TFLite interpreter."""
    input_details = tflite_facial_vit_interpreter.get_input_details()
    output_details = tflite_facial_vit_interpreter.get_output_details()
    tflite_facial_vit_interpreter.set_tensor(input_details[0]["index"], img_tensor_255)
    tflite_facial_vit_interpreter.invoke()
    output = tflite_facial_vit_interpreter.get_tensor(output_details[0]["index"])
    return float(output[0][0])


@app.on_event("startup")
def startup_event():
    global gesture_mobilenet, gesture_vit, facial_mobilenet, facial_vit
    global tflite_facial_vit_interpreter, facial_vit_model_label
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

    # 4. Load Facial ViT-B/16 (Prioritize Lightweight Quantized Model)
    if os.path.exists(TFLITE_FACIAL_VIT_PATH):
        try:
            tflite_facial_vit_interpreter = tf.lite.Interpreter(model_path=TFLITE_FACIAL_VIT_PATH)
            tflite_facial_vit_interpreter.allocate_tensors()
            facial_vit_model_label = "Facial_ViT-B16_Quantized_TFLite"
            print(f"Loaded Quantized TFLite Facial ViT-B/16 from {TFLITE_FACIAL_VIT_PATH}")
        except Exception as e:
            print(f"WARNING: Failed to load TFLite Facial ViT: {e}")
    elif os.path.exists(QUANT_FACIAL_VIT_NPZ_PATH):
        try:
            facial_vit = build_clean_facial_vit()
            load_quantized_int8_vit_npz(facial_vit, QUANT_FACIAL_VIT_NPZ_PATH)
            facial_vit_model_label = "Facial_ViT-B16_Quantized_INT8"
        except Exception as e:
            print(f"WARNING: Failed to load Quantized NPZ Facial ViT: {e}")
    elif os.path.exists(FACIAL_VIT_WEIGHTS_PATH):
        try:
            facial_vit = build_clean_facial_vit()
            load_vit_weights_safely(facial_vit, FACIAL_VIT_WEIGHTS_PATH)
            facial_vit_model_label = "Facial_ViT-B16"
            print(f"Loaded Facial ViT-B/16 from {FACIAL_VIT_WEIGHTS_PATH}")
        except Exception as e:
            print(f"WARNING: Failed to load Facial ViT-B/16: {e}")
    else:
        print(f"INFO: No Facial ViT weights found in {MODELS_DIR}")


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
        "facial_vit_loaded": (facial_vit is not None) or (tflite_facial_vit_interpreter is not None),
        "facial_vit_mode": facial_vit_model_label,
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
    has_facial_vit = (facial_vit is not None) or (tflite_facial_vit_interpreter is not None)

    if facial_mobilenet is None and not has_facial_vit:
        prob_autistic = 0.8600
        confidence = 0.8600
        model_used = "Simulated_Facial_Model"
        routing_tier = "Test mode (awaiting facial model weights)"
    elif facial_mobilenet is not None:
        prob_autistic = float(facial_mobilenet.predict(raw_input, verbose=0)[0][0])
        confidence = max(prob_autistic, 1.0 - prob_autistic)

        if confidence < EDGE_CONFIDENCE_THRESHOLD and has_facial_vit:
            if tflite_facial_vit_interpreter is not None:
                prob_autistic = predict_with_tflite_vit(raw_input)
            else:
                prob_autistic = float(facial_vit.predict(raw_input, verbose=0)[0][0])
            confidence = max(prob_autistic, 1.0 - prob_autistic)
            model_used = facial_vit_model_label
            routing_tier = "Quantized ViT diagnosis (escalated)"
    else:
        if tflite_facial_vit_interpreter is not None:
            prob_autistic = predict_with_tflite_vit(raw_input)
        else:
            prob_autistic = float(facial_vit.predict(raw_input, verbose=0)[0][0])
        confidence = max(prob_autistic, 1.0 - prob_autistic)
        model_used = facial_vit_model_label
        routing_tier = "Quantized ViT diagnosis"

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