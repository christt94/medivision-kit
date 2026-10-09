"""
MediVision Kit — Export EEGNet → ONNX
Usage : python backend/scripts/export_eeg_onnx.py
"""
import numpy as np
from pathlib import Path
import torch, torch.nn as nn, onnx

OUTPUT = Path(__file__).parent.parent / "data" / "models" / "signal" / "eeg_classifier.onnx"

class EEGNet(nn.Module):
    def __init__(self, n_ch=19, n_t=256, n_cls=7, F1=8, D=2, F2=16, drop=0.25):
        super().__init__()
        self.b1 = nn.Sequential(nn.Conv2d(1,F1,(1,64),padding=(0,32),bias=False), nn.BatchNorm2d(F1))
        self.b2 = nn.Sequential(nn.Conv2d(F1,F1*D,(n_ch,1),groups=F1,bias=False), nn.BatchNorm2d(F1*D), nn.ELU(), nn.AvgPool2d((1,4)), nn.Dropout(drop))
        self.b3 = nn.Sequential(nn.Conv2d(F1*D,F2,(1,16),padding=(0,8),bias=False), nn.BatchNorm2d(F2), nn.ELU(), nn.AvgPool2d((1,8)), nn.Dropout(drop))
        self.fc = nn.Linear(F2*((n_t//4)//8), n_cls)
        self.sm = nn.Softmax(dim=1)
    def forward(self, x):
        x = self.b1(x.unsqueeze(1)); x = self.b2(x); x = self.b3(x)
        logits = self.fc(x.flatten(1)); return logits, self.sm(logits)

print("[1/4] Construction du modèle EEGNet...")
model = EEGNet()
optimizer = torch.optim.Adam(model.parameters(), lr=1e-3)
criterion = nn.CrossEntropyLoss()
print("[2/4] Entraînement rapide (données synthétiques — 10 epochs)...")
X = torch.randn(200, 19, 256); y = torch.tensor(list(range(7))*28 + [0,0,0,0])[:200]
model.train()
for ep in range(10):
    optimizer.zero_grad(); loss = criterion(model(X)[0], y); loss.backward(); optimizer.step()
    print(f"  Epoch {ep+1}/10 — loss: {loss.item():.4f}")
print("[3/4] Export ONNX...")
model.eval()
torch.onnx.export(model, torch.randn(1,19,256), str(OUTPUT),
    export_params=True, opset_version=17, input_names=["input"],
    output_names=["logits","probabilities"],
    dynamic_axes={"input":{0:"batch"},"logits":{0:"batch"},"probabilities":{0:"batch"}})
onnx.checker.check_model(onnx.load(str(OUTPUT)))
print(f"[4/4] ✓ Modèle exporté → {OUTPUT} ({OUTPUT.stat().st_size/1e6:.2f} Mo)")
print("⚠ Données synthétiques. Réentraîner sur PhysioNet Sleep-EDF pour la prod.")
