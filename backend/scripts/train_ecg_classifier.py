"""
Train a lightweight ResNet1D on PTB-XL data and export to ONNX.
Uses the 10 downloaded records as a micro demo.
For production: download full PTB-XL (21,799 records) and retrain.
"""
import json, os, sys
import numpy as np
import pandas as pd
import torch
import torch.nn as nn
from torch.utils.data import Dataset, DataLoader
from sklearn.preprocessing import LabelEncoder
from sklearn.model_selection import train_test_split

# ── Labels ──────────────────────────────────────────────────────────────────
SCP_CLASSES = ["NORM", "MI", "STTC", "CD", "HYP", "OTHER"]

# ── Dataset ─────────────────────────────────────────────────────────────────
class PTBXLDataset(Dataset):
    def __init__(self, records, n_samples=1000):
        self.data, self.labels = [], []
        le = LabelEncoder()
        le.fit(SCP_CLASSES)
        for rec in records:
            sig = pd.read_csv(rec["file"]).values.T.astype(np.float32)  # (12, n)
            # Normalize per channel
            sig = (sig - sig.mean(axis=1, keepdims=True)) / (sig.std(axis=1, keepdims=True) + 1e-8)
            # Fixed length: crop or pad to n_samples
            if sig.shape[1] >= n_samples:
                sig = sig[:, :n_samples]
            else:
                sig = np.pad(sig, ((0,0),(0, n_samples - sig.shape[1])))
            dx = rec["diagnosis"] if rec["diagnosis"] in SCP_CLASSES else "OTHER"
            self.data.append(sig)
            self.labels.append(le.transform([dx])[0])
        self.le = le

    def __len__(self): return len(self.data)
    def __getitem__(self, i):
        return torch.tensor(self.data[i]), torch.tensor(self.labels[i], dtype=torch.long)

# ── Model: ResNet1D (lightweight) ───────────────────────────────────────────
class ResBlock1D(nn.Module):
    def __init__(self, ch):
        super().__init__()
        self.net = nn.Sequential(
            nn.Conv1d(ch, ch, 7, padding=3), nn.BatchNorm1d(ch), nn.ReLU(),
            nn.Conv1d(ch, ch, 7, padding=3), nn.BatchNorm1d(ch)
        )
        self.relu = nn.ReLU()

    def forward(self, x): return self.relu(x + self.net(x))

class ECGResNet1D(nn.Module):
    def __init__(self, n_leads=12, n_classes=6):
        super().__init__()
        self.stem = nn.Sequential(
            nn.Conv1d(n_leads, 32, 15, padding=7), nn.BatchNorm1d(32), nn.ReLU(),
            nn.MaxPool1d(2)
        )
        self.blocks = nn.Sequential(
            ResBlock1D(32), nn.MaxPool1d(2),
            ResBlock1D(32), nn.MaxPool1d(2),
            ResBlock1D(32), nn.AdaptiveAvgPool1d(16)
        )
        self.head = nn.Sequential(
            nn.Flatten(),
            nn.Linear(32 * 16, 64), nn.ReLU(), nn.Dropout(0.3),
            nn.Linear(64, n_classes)
        )

    def forward(self, x): return self.head(self.blocks(self.stem(x)))

# ── Train ────────────────────────────────────────────────────────────────────
with open("data/samples/ptbxl/manifest.json") as f:
    records = json.load(f)

print(f"Records available: {len(records)}")
print(f"Classes: {[r['diagnosis'] for r in records]}\n")

# With only 10 records, train on all, validate on all (demo only)
# In production: split 80/20 on full 21,799 records
dataset = PTBXLDataset(records, n_samples=1000)
loader  = DataLoader(dataset, batch_size=min(4, len(dataset)), shuffle=True)

model     = ECGResNet1D(n_leads=12, n_classes=len(SCP_CLASSES))
optimizer = torch.optim.Adam(model.parameters(), lr=1e-3)
criterion = nn.CrossEntropyLoss()

print("Training ResNet1D ECG classifier (10 epochs demo)...")
model.train()
for epoch in range(10):
    total_loss, correct, total = 0, 0, 0
    for x, y in loader:
        optimizer.zero_grad()
        out = model(x)
        loss = criterion(out, y)
        loss.backward()
        optimizer.step()
        total_loss += loss.item()
        correct += (out.argmax(1) == y).sum().item()
        total += len(y)
    print(f"  Epoch {epoch+1:>2}/10 | Loss: {total_loss/len(loader):.4f} | Acc: {correct/total:.2%}")

# ── Export to ONNX ────────────────────────────────────────────────────────────
os.makedirs("models/signal", exist_ok=True)
onnx_path = "models/signal/ecg_classifier.onnx"
model.eval()
dummy = torch.zeros(1, 12, 1000)
torch.onnx.export(
    model, dummy, onnx_path,
    input_names=["ecg_signal"],
    output_names=["logits"],
    dynamic_axes={"ecg_signal": {0: "batch"}},
    opset_version=17
)
print(f"\n✓ ONNX model exported → {onnx_path}")
print(f"  Size: {os.path.getsize(onnx_path)/1024:.1f} KB")

# Save label mapping
label_map = {i: cls for i, cls in enumerate(SCP_CLASSES)}
with open("models/signal/ecg_labels.json", "w") as f:
    json.dump(label_map, f, indent=2)
print(f"✓ Label map saved → models/signal/ecg_labels.json")
print(f"\nLabel mapping: {label_map}")
