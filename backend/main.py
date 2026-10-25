import io
import os
import sqlite3
import numpy as np
from PIL import Image
from fastapi import FastAPI, UploadFile, File, HTTPException
from fastapi.middleware.cors import CORSMiddleware

import tensorflow as tf
import keras
import tf_keras
import tensorflow_hub as hub

app = FastAPI(title="ASD-Sense Inference API", version="1.0")

# Enable CORS so Flutter Web (Docker) and mobile devices can call the API
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

DB_PATH = "asd_sense.db"
SCHEMA_PATH = "asd_sense_database_schema.sql"

GESTURE_MOBILENET_PATH = "models/best_mobilenet.keras"
GESTURE_VIT_WEIGHTS_PATH = "models/best_gesture_vit.weights.h5"
VIT_HUB_URL = "https://tfhub.dev/sayakpaul/vit_b16_fe/1"

IMG_SIZE = (224, 224)
EDGE_CONFIDENCE_THRESHOLD = 0.85  # Escalate to Cloud ViT if MobileNet confidence is below 85%
INCONCLUSIVE_THRESHOLD = 0.60

gesture_mobilenet = None
gesture_vit = None


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


@app.on_event("startup")
def startup_event():
    global gesture_mobilenet, gesture_vit
    init_db()

    if os.path.exists(GESTURE_MOBILENET_PATH):
        gesture_mobilenet = keras.models.load_model(GESTURE_MOBILENET_PATH, compile=False)
        print(f"Loaded Gesture MobileNetV2 from {GESTURE_MOBILENET_PATH}")
    else:
        print(f"WARNING: Gesture MobileNetV2 not found at {GESTURE_MOBILENET_PATH}")

    if os.path.exists(GESTURE_VIT_WEIGHTS_PATH):
        gesture_vit = build_gesture_vit()
        gesture_vit.load_weights(GESTURE_VIT_WEIGHTS_PATH)
        print(f"Loaded Gesture ViT-B/16 weights from {GESTURE_VIT_WEIGHTS_PATH}")
    else:
        print(f"INFO: Gesture ViT weights not found at {GESTURE_VIT_WEIGHTS_PATH} (running MobileNetV2 standalone).")


def preprocess_for_mobilenet(image_bytes: bytes) -> np.ndarray:
    """MobileNetV2 has preprocess_input inside the model graph; pass raw [0, 255] float32."""
    image = Image.open(io.BytesIO(image_bytes)).convert("RGB").resize(IMG_SIZE)
    img_array = np.asarray(image, dtype=np.float32)
    return np.expand_dims(img_array, axis=0)


def preprocess_for_vit(image_bytes: bytes) -> np.ndarray:
    """ViT expects external scaling to [-1, 1] via (img / 127.5) - 1.0."""
    image = Image.open(io.BytesIO(image_bytes)).convert("RGB").resize(IMG_SIZE)
    img_array = (np.asarray(image, dtype=np.float32) / 127.5) - 1.0
    return np.expand_dims(img_array, axis=0)


@app.get("/")
def read_root():
    return {
        "status": "ASD-Sense Backend Online",
        "gesture_mobilenet_loaded": gesture_mobilenet is not None,
        "gesture_vit_loaded": gesture_vit is not None,
    }


@app.post("/predict/gesture")
async def analyze_gesture(file: UploadFile = File(...), child_id: int = 1):
    image_bytes = await file.read()
    model_used = "Gesture_MobileNetV2"
    routing_tier = "Edge / API screening"

    # Fallback mode while waiting for model weight files
    if gesture_mobilenet is None and gesture_vit is None:
        _ = preprocess_for_mobilenet(image_bytes)  # Verify image decoding works
        prob_autistic = 0.8850
        confidence = 0.8850
        model_used = "Simulated_Gesture_Model"
        routing_tier = "Test mode (awaiting model weights)"
    # Stage 1: Run MobileNetV2 Edge Screening
    elif gesture_mobilenet is not None:
        mobilenet_input = preprocess_for_mobilenet(image_bytes)
        prob_autistic = float(gesture_mobilenet.predict(mobilenet_input, verbose=0)[0][0])
        confidence = max(prob_autistic, 1.0 - prob_autistic)

        # Stage 2: Escalate to Cloud ViT-B/16 if confidence is below threshold and ViT is loaded
        if confidence < EDGE_CONFIDENCE_THRESHOLD and gesture_vit is not None:
            vit_input = preprocess_for_vit(image_bytes)
            prob_autistic = float(gesture_vit.predict(vit_input, verbose=0)[0][0])
            confidence = max(prob_autistic, 1.0 - prob_autistic)
            model_used = "Gesture_ViT-B16"
            routing_tier = "Cloud clinical diagnosis (escalated)"
    else:
        vit_input = preprocess_for_vit(image_bytes)
        prob_autistic = float(gesture_vit.predict(vit_input, verbose=0)[0][0])
        confidence = max(prob_autistic, 1.0 - prob_autistic)
        model_used = "Gesture_ViT-B16"
        routing_tier = "Cloud clinical diagnosis"

    # Stage 1: Run MobileNetV2 Edge Screening
    if gesture_mobilenet is not None:
        mobilenet_input = preprocess_for_mobilenet(image_bytes)
        prob_autistic = float(gesture_mobilenet.predict(mobilenet_input, verbose=0)[0][0])
        confidence = max(prob_autistic, 1.0 - prob_autistic)

        # Stage 2: Escalate to Cloud ViT-B/16 if confidence is below threshold and ViT is loaded
        if confidence < EDGE_CONFIDENCE_THRESHOLD and gesture_vit is not None:
            vit_input = preprocess_for_vit(image_bytes)
            prob_autistic = float(gesture_vit.predict(vit_input, verbose=0)[0][0])
            confidence = max(prob_autistic, 1.0 - prob_autistic)
            model_used = "Gesture_ViT-B16"
            routing_tier = "Cloud clinical diagnosis (escalated)"
    else:
        vit_input = preprocess_for_vit(image_bytes)
        prob_autistic = float(gesture_vit.predict(vit_input, verbose=0)[0][0])
        confidence = max(prob_autistic, 1.0 - prob_autistic)
        model_used = "Gesture_ViT-B16"
        routing_tier = "Cloud clinical diagnosis"

    # Map to SQLite CHECK constraint values: ('autistic', 'non_autistic', 'inconclusive')
    if confidence < INCONCLUSIVE_THRESHOLD:
        predicted_class = "inconclusive"
    elif prob_autistic >= 0.5:
        predicted_class = "autistic"
    else:
        predicted_class = "non_autistic"

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
                file.filename,
                routing_tier,
            ),
        )
        screening_id = cursor.lastrowid
        conn.commit()

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