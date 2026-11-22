"""Select the Gesture ViT checkpoint without replacing the historical model file."""

import os
from pathlib import Path

ENV_NAME = "ASD_SENSE_GESTURE_VIT_WEIGHTS_PATH"
DEFAULT_FILENAME = "best_gesture_vit.weights.h5"


def choose_gesture_vit_weights_path(models_dir: str | os.PathLike[str]) -> str:
    """Use a configured absolute H5 path, otherwise retain the legacy default.

    An explicitly configured but missing file is deliberately *not* replaced
    with the old weights. The caller logs that the selected model is missing.
    """
    override = os.environ.get(ENV_NAME, "").strip()
    if not override:
        return str(Path(models_dir) / DEFAULT_FILENAME)

    selected = Path(os.path.expandvars(os.path.expanduser(override)))
    if not selected.is_absolute():
        raise ValueError(f"{ENV_NAME} must be an absolute path: {override!r}")
    return str(selected)
