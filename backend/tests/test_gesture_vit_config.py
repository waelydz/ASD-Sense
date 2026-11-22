"""Check checkpoint selection without loading TensorFlow or model weights."""

import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from gesture_vit_config import (  # noqa: E402
    ENV_NAME,
    choose_gesture_vit_weights_path,
)


def test_default_remains_original_checkpoint(monkeypatch, tmp_path):
    monkeypatch.delenv(ENV_NAME, raising=False)
    assert choose_gesture_vit_weights_path(tmp_path) == str(tmp_path / "best_gesture_vit.weights.h5")


def test_blank_override_keeps_default(monkeypatch, tmp_path):
    monkeypatch.setenv(ENV_NAME, "  ")
    assert choose_gesture_vit_weights_path(tmp_path) == str(tmp_path / "best_gesture_vit.weights.h5")


def test_explicit_retrained_path_is_selected(monkeypatch, tmp_path):
    retrained = tmp_path / "best_gesture_vit_retrained.weights.h5"
    monkeypatch.setenv(ENV_NAME, str(retrained))
    assert choose_gesture_vit_weights_path(tmp_path / "models") == str(retrained)


def test_missing_override_does_not_fallback(monkeypatch, tmp_path):
    missing = tmp_path / "not_downloaded.weights.h5"
    monkeypatch.setenv(ENV_NAME, str(missing))
    assert choose_gesture_vit_weights_path(tmp_path / "models") == str(missing)


def test_relative_override_is_rejected(monkeypatch, tmp_path):
    monkeypatch.setenv(ENV_NAME, "models/best_gesture_vit_retrained.weights.h5")
    with pytest.raises(ValueError, match="must be an absolute path"):
        choose_gesture_vit_weights_path(tmp_path)
