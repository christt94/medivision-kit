"""Export already-trained model to ONNX using legacy API."""
import torch, os, json, sys
sys.path.insert(0, ".")

# Re-import model definition
from scripts.train_ecg_classifier import ECGResNet1D, SCP_CLASSES, PTBXLDataset, DataLoader

import json
with open("data/samples/ptbxl/manifest.json") as f:
    records = json.load(f)

dataset = PTBXLDataset(records, n_samples=1000)
loader  = DataLoader(dataset, batch_size=4, shuffle=True)

# Re-train quickly
import torch.nn as nn
model     = ECGResNet1D(n_leads=12, n_classes=len(SCP_CLASSES))
optimizer = torch.optim.Adam(model.parameters(), lr=1e-3)
criterion = nn.CrossEntropyLoss()
model.train()
for epoch in range(10):
    for x, y in loader:
        optimizer.zero_grad()
        loss = criterion(model(x), y)
        loss.backward()
        optimizer.step()
print("✓ Model trained")

# Export with legacy API (no onnxscript needed)
os.makedirs("models/signal", exist_ok=True)
onnx_path = "models/signal/ecg_classifier.onnx"
model.eval()
dummy = torch.zeros(1, 12, 1000)
with torch.no_grad():
    torch.onnx.export(
        model, dummy, onnx_path,
        export_params=True,
        opset_version=14,                      # ← 14 instead of 17, no onnxscript needed
        do_constant_folding=True,
        input_names=["ecg_signal"],
        output_names=["logits"],
        dynamic_axes={"ecg_signal": {0: "batch"}},
    )

print(f"✓ ONNX exported → {onnx_path}  ({os.path.getsize(onnx_path)/1024:.1f} KB)")

label_map = {i: cls for i, cls in enumerate(SCP_CLASSES)}
with open("models/signal/ecg_labels.json", "w") as f:
    json.dump(label_map, f, indent=2)
print(f"✓ Labels saved  → models/signal/ecg_labels.json")
print(f"  Map: {label_map}")
