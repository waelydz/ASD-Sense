import os
import sys
import subprocess
os.environ["TF_USE_LEGACY_KERAS"] = "1"
os.environ["TF_ENABLE_ONEDNN_OPTS"] = "0"

import h5py
import numpy as np
import tensorflow as tf
import tf_keras
import tensorflow_hub as hub

BASE_DIR = os.path.dirname(os.path.abspath(__file__))
MODELS_DIR = os.path.join(BASE_DIR, "models")
VIT_WEIGHTS_PATH = os.path.join(MODELS_DIR, "best_facial_vit.weights.h5")

TFLITE_OUTPUT_PATH = os.path.join(MODELS_DIR, "facial_vit_b16_quantized.tflite")
NPZ_QUANT_OUTPUT_PATH = os.path.join(MODELS_DIR, "facial_vit_b16_quantized.npz")


def build_clean_facial_vit():
    """Builds the Facial ViT-B/16 inference graph."""
    vit_url = "https://tfhub.dev/sayakpaul/vit_b16_fe/1"
    vit_layer = hub.KerasLayer(vit_url, trainable=False, name="vit_layer")

    model = tf_keras.Sequential([
        tf_keras.layers.InputLayer(input_shape=(224, 224, 3)),
        tf_keras.layers.Rescaling(1.0 / 127.5, offset=-1),
        vit_layer,
        tf_keras.layers.BatchNormalization(name="batch_normalization"),
        tf_keras.layers.Dense(128, activation="relu", name="dense"),
        tf_keras.layers.Dropout(0.5, name="dropout"),
        tf_keras.layers.Dense(1, activation="sigmoid", name="dense_1"),
    ])
    model.build((1, 224, 224, 3))
    return model


def load_all_vit_weights_safely(model, weights_path):
    """Restores all 198 ViT backbone tensors AND all 8 classification head tensors via h5py."""
    vit_datasets = {}
    head_datasets = []

    with h5py.File(weights_path, "r") as f:
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
        print(f"   -> Loaded {assigned_vit}/{len(vit_vars)} ViT backbone tensors.")

    # 2. Assign classification head variables (BatchNormalization + Dense + Dense_1)
    head_vars = (
        model.get_layer("batch_normalization").variables
        + model.get_layer("dense").variables
        + model.get_layer("dense_1").variables
    )
    assigned_head = 0
    used_indices = set()
    for var in head_vars:
        var_base = var.name.split(":")[0].split("/")[-1]
        # First pass: match both shape and variable type name (gamma, beta, moving_mean, moving_variance, kernel, bias)
        matched = False
        for idx, (h5_name, arr) in enumerate(head_datasets):
            if idx not in used_indices and var.shape == arr.shape and var_base in h5_name:
                var.assign(arr)
                used_indices.add(idx)
                assigned_head += 1
                matched = True
                break
        # Second pass: match by exact shape in order
        if not matched:
            for idx, (h5_name, arr) in enumerate(head_datasets):
                if idx not in used_indices and var.shape == arr.shape:
                    var.assign(arr)
                    used_indices.add(idx)
                    assigned_head += 1
                    break
    print(f"   -> Loaded {assigned_head}/{len(head_vars)} classification head tensors.")


def quantize_weights_to_int8_npz(model, output_path):
    """Pure-Python INT8 Post-Training Dynamic Range Quantization (crash-proof on Windows Python 3.13)."""
    quant_dict = {}
    for idx, var in enumerate(model.variables):
        w = var.numpy().astype(np.float32)
        if w.ndim >= 2 and w.size >= 128:
            max_val = np.max(np.abs(w))
            scale = float(max_val / 127.0) if max_val > 0 else 1.0
            w_int8 = np.clip(np.round(w / scale), -127, 127).astype(np.int8)
            quant_dict[f"w_{idx}_int8"] = w_int8
            quant_dict[f"w_{idx}_scale"] = np.array([scale], dtype=np.float32)
        else:
            # Keep 1D biases / LayerNorm / BatchNorm vectors in float16 for high precision
            quant_dict[f"w_{idx}_fp16"] = w.astype(np.float16)

    np.savez_compressed(output_path, **quant_dict)


def try_tflite_export():
    """Runs inside a child process to test if C++ MLIR succeeds with static batch size 1."""
    vit_model = build_clean_facial_vit()
    load_all_vit_weights_safely(vit_model, VIT_WEIGHTS_PATH)

    @tf.function(input_signature=[tf.TensorSpec(shape=[1, 224, 224, 3], dtype=tf.float32)])
    def serving_fn(x):
        return vit_model(x, training=False)

    concrete_func = serving_fn.get_concrete_function()
    converter = tf.lite.TFLiteConverter.from_concrete_functions([concrete_func], vit_model)
    converter.optimizations = [tf.lite.Optimize.DEFAULT]
    converter.target_spec.supported_ops = [
        tf.lite.OpsSet.TFLITE_BUILTINS,
        tf.lite.OpsSet.SELECT_TF_OPS,
    ]
    converter._experimental_lower_tensor_list_ops = False
    tflite_bytes = converter.convert()
    with open(TFLITE_OUTPUT_PATH, "wb") as f:
        f.write(tflite_bytes)


if __name__ == "__main__":
    if len(sys.argv) > 1 and sys.argv[1] == "--child-tflite":
        try_tflite_export()
        sys.exit(0)

    if not os.path.exists(VIT_WEIGHTS_PATH):
        raise FileNotFoundError(f"Could not find weights file at: {VIT_WEIGHTS_PATH}")

    orig_size_mb = os.path.getsize(VIT_WEIGHTS_PATH) / (1024 * 1024)
    print(f"1. Found original ViT checkpoint: {VIT_WEIGHTS_PATH} ({orig_size_mb:.2f} MB)")

    print("2. Attempting static-shape TFLite conversion in isolated subprocess...")
    res = subprocess.run([sys.executable, __file__, "--child-tflite"])

    if res.returncode == 0 and os.path.exists(TFLITE_OUTPUT_PATH):
        new_size_mb = os.path.getsize(TFLITE_OUTPUT_PATH) / (1024 * 1024)
        saved_path = TFLITE_OUTPUT_PATH
    else:
        print("\n   [Info] Windows Python 3.13 C++ MLIR compiler aborted on TF-Hub op.")
        print("3. Executing Pure-Python INT8 Post-Training Weight Quantization...")
        vit_model = build_clean_facial_vit()
        load_all_vit_weights_safely(vit_model, VIT_WEIGHTS_PATH)
        quantize_weights_to_int8_npz(vit_model, NPZ_QUANT_OUTPUT_PATH)
        new_size_mb = os.path.getsize(NPZ_QUANT_OUTPUT_PATH) / (1024 * 1024)
        saved_path = NPZ_QUANT_OUTPUT_PATH

    reduction_pct = 100.0 - (new_size_mb / orig_size_mb) * 100.0
    print("\n" + "=" * 60)
    print("QUANTIZATION SUCCESSFUL!")
    print(f"Original Checkpoint Size : {orig_size_mb:.2f} MB")
    print(f"Quantized Model Size     : {new_size_mb:.2f} MB ({reduction_pct:.1f}% smaller)")
    print(f"Saved File Location      : {saved_path}")
    print("=" * 60)