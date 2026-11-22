"""Fast, model-free routing-policy regression tests.

Extracts only relevant scoring functions from the actual backend/main.py AST;
this avoids importing TensorFlow and loading ~1GB model files while still
exercising the original scoring logic. Does NOT replace a real-model smoke test.
"""
import ast
from pathlib import Path

import pytest

MAIN_PATH = Path(__file__).resolve().parents[1] / 'main.py'


def load_scoring_namespace():
    source = MAIN_PATH.read_text(encoding='utf-8')
    tree = ast.parse(source, filename=str(MAIN_PATH))
    names = {'score_gesture', 'score_facial', 'classify'}
    funcs = [node for node in tree.body if isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef)) and node.name in names]
    assert {node.name for node in funcs} == names, 'Expected scoring functions missing from backend/main.py'
    code = compile(ast.Module(body=funcs, type_ignores=[]), str(MAIN_PATH), 'exec')
    ns = {
        'EDGE_CONFIDENCE_THRESHOLD': None,
        'INCONCLUSIVE_THRESHOLD': None,
        'preprocess_raw_255': lambda raw: raw,
        'preprocess_external_vit': lambda raw: raw,
        'predict_with_tflite_vit': lambda img: (_ for _ in ()).throw(AssertionError('unexpected TFLite call')),
        'gesture_mobilenet': None, 'gesture_vit': None,
        'facial_mobilenet': None, 'facial_vit': None,
        'tflite_facial_vit_interpreter': None,
        'facial_vit_model_label': 'Facial_ViT-B16_Quantized_INT8',
    }
    for node in tree.body:
        if isinstance(node, ast.Assign) and len(node.targets) == 1 and isinstance(node.targets[0], ast.Name):
            if node.targets[0].id in ('EDGE_CONFIDENCE_THRESHOLD', 'INCONCLUSIVE_THRESHOLD'):
                ns[node.targets[0].id] = ast.literal_eval(node.value)
    assert ns['EDGE_CONFIDENCE_THRESHOLD'] is not None
    assert ns['INCONCLUSIVE_THRESHOLD'] is not None
    exec(code, ns)
    return ns


class FakeModel:
    def __init__(self, probability):
        self.probability = probability
        self.calls = 0

    def predict(self, images, verbose=0):
        self.calls += 1
        return [[self.probability]]


@pytest.mark.parametrize('modality', ('facial', 'gesture'))
@pytest.mark.parametrize('probability,should_escalate', [(0.849, True), (0.850, False), (0.851, False), (0.151, True), (0.150, False)])
def test_escalation_boundary(modality, probability, should_escalate):
    ns = load_scoring_namespace()
    assert ns['EDGE_CONFIDENCE_THRESHOLD'] == 0.85
    edge = FakeModel(probability)
    vit = FakeModel(0.75)
    ns[f'{modality}_mobilenet'] = edge
    ns[f'{modality}_vit'] = vit
    ns[f'score_{modality}'](b'synthetic-placeholder-not-a-real-image')
    assert edge.calls == 1
    assert vit.calls == int(should_escalate)


@pytest.mark.parametrize('modality', ('facial', 'gesture'))
def test_missing_second_tier_keeps_mobilenet(modality):
    ns = load_scoring_namespace()
    edge = FakeModel(0.60)
    ns[f'{modality}_mobilenet'] = edge
    ns[f'{modality}_vit'] = None
    probability, confidence, model, routing = ns[f'score_{modality}'](b'placeholder')
    assert edge.calls == 1
    assert model.endswith('MobileNetV2')
    assert probability == pytest.approx(0.60)
    assert confidence == pytest.approx(0.60)


@pytest.mark.parametrize('probability,confidence,expected', [
    (0.5, 0.59, 'inconclusive'),
    (0.5, 0.60, 'autistic'),
    (0.4, 0.60, 'non_autistic'),
    (0.7, 0.70, 'autistic'),
])
def test_inconclusive_boundary(probability, confidence, expected):
    ns = load_scoring_namespace()
    assert ns['INCONCLUSIVE_THRESHOLD'] == 0.60
    assert ns['classify'](probability, confidence) == expected


def test_config_values_are_exact():
    tree = ast.parse(MAIN_PATH.read_text(encoding='utf-8'))
    config = {}
    for node in tree.body:
        if isinstance(node, ast.Assign) and len(node.targets) == 1 and isinstance(node.targets[0], ast.Name):
            if node.targets[0].id in ('EDGE_CONFIDENCE_THRESHOLD', 'INCONCLUSIVE_THRESHOLD'):
                config[node.targets[0].id] = ast.literal_eval(node.value)
    assert config['EDGE_CONFIDENCE_THRESHOLD'] == 0.85
    assert config['INCONCLUSIVE_THRESHOLD'] == 0.60
