"""Optional CPU MedGemma adapter for preliminary imaging assistance."""

from pathlib import Path
from typing import Any

_MODEL_ID = "google/medgemma-1.5-4b-it"
_adapter = None


def _load_image(path: Path):
    from PIL import Image

    if path.suffix.lower() in {".dcm", ".dicom"}:
        import numpy as np
        import pydicom

        dataset = pydicom.dcmread(str(path), force=True)
        pixels = dataset.pixel_array.astype(np.float32)
        pixels -= pixels.min()
        peak = pixels.max()
        if peak > 0:
            pixels /= peak
        return Image.fromarray((pixels * 255).astype(np.uint8)).convert("RGB")
    return Image.open(path).convert("RGB")


class MedGemmaCpuAdapter:
    def __init__(self):
        import torch
        from transformers import AutoModelForImageTextToText, AutoProcessor

        self.model = AutoModelForImageTextToText.from_pretrained(
            _MODEL_ID,
            torch_dtype=torch.float32,
            device_map="cpu",
            low_cpu_mem_usage=True,
        )
        self.processor = AutoProcessor.from_pretrained(_MODEL_ID)
        self.model.eval()

    def analyze(self, image_path: Path, modality: str, indication: str) -> dict[str, Any]:
        import torch

        image = _load_image(image_path)
        prompt = (
            "You are assisting a qualified clinician. Review this medical image "
            f"from the modality {modality}. Clinical indication: {indication or 'not provided'}. "
            "Provide a concise preliminary description of visible findings, image quality "
            "limitations, and suggested follow-up questions. Do not claim a definitive "
            "diagnosis, and state that clinician verification is required."
        )
        messages = [{
            "role": "user",
            "content": [
                {"type": "image", "image": image},
                {"type": "text", "text": prompt},
            ],
        }]
        inputs = self.processor.apply_chat_template(
            messages,
            add_generation_prompt=True,
            tokenize=True,
            return_dict=True,
            return_tensors="pt",
        )
        inputs = {key: value.to("cpu") if hasattr(value, "to") else value
                  for key, value in inputs.items()}
        input_length = inputs["input_ids"].shape[-1]
        with torch.inference_mode():
            generated = self.model.generate(
                **inputs,
                max_new_tokens=256,
                do_sample=False,
            )
        text = self.processor.decode(
            generated[0][input_length:], skip_special_tokens=True
        ).strip()
        return {
            "text": text,
            "model": _MODEL_ID,
            "requires_clinician_review": True,
        }


def analyze_with_medgemma(image_path: Path, modality: str, indication: str) -> dict[str, Any]:
    global _adapter
    if _adapter is None:
        _adapter = MedGemmaCpuAdapter()
    return _adapter.analyze(image_path, modality, indication)
