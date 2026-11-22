# Gesture ViT checkpoint selection

The backend loads the **historical** Gesture ViT checkpoint by default:

`backend/models/best_gesture_vit.weights.h5`

To test the independently evaluated Nov 22, 2026 **retrained** checkpoint, set the
`ASD_SENSE_GESTURE_VIT_WEIGHTS_PATH` environment variable to its absolute local H5
path **before** starting the FastAPI process. Example (PowerShell):

```powershell
$env:ASD_SENSE_GESTURE_VIT_WEIGHTS_PATH = "$env:USERPROFILE\Desktop\Fall27\GestureViT_Candidate\best_gesture_vit_retrained.weights.h5"
cd "$env:USERPROFILE\Desktop\Fall27\Senior\backend"
.\.venv\Scripts\python.exe -m uvicorn main:app --host 127.0.0.1 --port 8000
```

The override selects the checkpoint used by the **existing** `/predict/gesture`
and `/api/clinic/predict/gesture` routes. It does not create another endpoint or
change the MobileNet-to-ViT confidence threshold (0.85). The facial models are
unchanged. **Restart FastAPI** after changing the environment variable.

To revert in the current PowerShell session, stop the backend and run:

```powershell
Remove-Item Env:ASD_SENSE_GESTURE_VIT_WEIGHTS_PATH -ErrorAction SilentlyContinue
```

The environment variable defaults to the legacy H5 when unset or blank. An
explicit non-existent file does **not** silently fall back to the legacy file;
the startup log reports that the selected checkpoint is absent. Use an
absolute path (not a relative path). No H5 binaries should be committed to Git.

The candidate H5 SHA-256 is:
`b59199d1919437823c4d6f3344e5663ed4798b0a12b9b6c405297ad9312701a5`

The checkpoints have been uploaded to a **draft** release tagged
`model-checkpoints-2026-11-22`; asset publication and redistribution rights
have not been established yet. Do not treat a draft release as a public
artifact URL or automatically download from it in production.

Candidate evaluation: 98.82% accuracy (251/254) on a 254-image held-out test
partition (TN 83, FP 3, FN 0, TP 168). This is screening research, not a
clinical diagnosis; subject-level independence and external generalization
remain unverified. The older 99.14% metric was a *different validation split*,
not a result from this held-out test.
