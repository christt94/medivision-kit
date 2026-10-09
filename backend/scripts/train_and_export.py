import torch, torch.nn as nn, os, json
import numpy as np, pandas as pd
from torch.utils.data import Dataset, DataLoader
from sklearn.preprocessing import LabelEncoder

SCP_CLASSES = ["NORM", "MI", "STTC", "CD", "HYP", "OTHER"]

class PTBXLDataset(Dataset):
    def __init__(self, records, n_samples=1000):
        self.data, self.labels = [], []
        le = LabelEncoder().fit(SCP_CLASSES)
        for rec in records:
            sig = pd.read_csv(rec["file"]).values.T.astype(np.float32)
            sig = (sig - sig.mean(axis=1, keepdims=True)) / (sig.std(axis=1, keepdims=True) + 1e-8)
            if sig.shape[1] >= n_samples:
                sig = sig[:, :n_samples]
            else:
                sig = np.pad(sig, ((0,0),(0, n_samples - sig.shape[1])))
            dx = rec["diagnosis"] if rec["diagnosis"] in SCP_CLASSES else "OTHER"
            self.data.append(sig)
            self.labels.append(le.transform([dx])[0])
    def __len__(self): return len(self.data)
    def __getitem__(self, i):
        return torch.tensor(self.data[i]), torch.tensor(self.labels[i], dtype=torch.long)

class ResBlock1D(nn.Module):
    def __init__(self, ch):
        super().__init__()
        self.net = nn.Sequential(
            nn.Conv1d(ch, ch, 7, padding=3), nn.BatchNorm1d(ch), nn.ReLU(),
            nn.Conv1d(ch, ch, 7, padding=3), nn.BatchNorm1d(ch))
        self.relu = nn.ReLU()
    def forward(self, x): return self.relu(x + self.net(x))

class ECGResNet1D(nn.Module):
    def __init__(self, n_leads=12, n_classes=6):
        super().__init__()
        self.stem = nn.Sequential(
            nn.Conv1d(n_leads, 32, 15, padding=7), nn.BatchNorm1d(32), nn.ReLU(), nn.MaxPool1d(2))
        self.blocks = nn.Sequential(
            ResBlock1D(32), nn.MaxPool1d(2),
            ResBlock1D(32), nn.MaxPool1d(2),
            ResBlock1D(32), nn.AdaptiveAvgPool1d(16))
        self.head = nn.Sequential(
            nn.Flatten(), nn.Linear(32*16, 64), nn.ReLU(), nn.Dropout(0.3), nn.Linear(64, n_classes))
    def forward(self, x): return self.head(self.blocks(self.stem(x)))

# ── Train ────────────────────────────────────────────────────────────────────
with open("data/samples/ptbxl/manifest.json") as f:
    records = json.load(f)

dataset = PTBXLDataset(records, n_samples=1000)
loader  = DataLoader(dataset, batch_size=4, shuffle=True)
model   = ECGResNet1D()
opt     = torch.optim.Adam(model.parameters(), lr=1e-3)
crit    = nn.CrossEntropyLoss()

print("Training...")
model.train()
for epoch in range(10):
    loss_sum, correct, total = 0, 0, 0
    for x, y in loader:
        opt.zero_grad()
        out = model(x)
        loss = crit(out, y)
        loss.backward(); opt.step()
        loss_sum += loss.item()
        correct += (out.argmax(1)==y).sum().item(); total += len(y)
    print(f"  Epoch {epoch+1:>2}/10 | Loss {loss_sum/len(loader):.4f} | Acc {correct/total:.0%}")

# ── Export ONNX (opset 14, no onnxscript needed) ─────────────────────────────
os.makedirs("models/signal", exist_ok=True)
onnx_path = "models/signal/ecg_classifier.onnx"
model.eval()
dummy = torch.zeros(1, 12, 1000)
with torch.no_grad():
    torch.onnx.export(
        model, dummy, onnx_path,
        export_params=True,
        opset_version=14,
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
