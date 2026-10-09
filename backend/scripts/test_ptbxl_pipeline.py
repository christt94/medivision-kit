"""Run ECG pipeline on all downloaded PTB-XL samples."""
import json, sys, os
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from app.services.ecg_pipeline import ECGPipeline

pipeline = ECGPipeline()
manifest_path = "data/samples/ptbxl/manifest.json"

with open(manifest_path) as f:
    records = json.load(f)

print(f"Testing MediVision ECG pipeline on {len(records)} real PTB-XL clinical ECGs\n")
print(f"{'ECG ID':>8} {'Age':>4} {'Sex':>4} {'True Dx':>10} {'HR':>6} {'Channels':>9} {'Duration':>9} {'Confidence':>11} {'Review':>20}")
print("─" * 95)

results = []
errors = []

for rec in records:
    context = {
        "patient_id": f"ptbxl_{rec['ecg_id']}",
        "age": int(rec["age"]) if rec["age"] else 0,
        "sexe": rec["sex"],
        "indication": f"PTB-XL — vraie étiquette: {rec['diagnosis']}"
    }
    try:
        result = pipeline.run(rec["file"], context)
        f = result["findings"]
        results.append({**rec, "pipeline_result": result})
        print(
            f"{rec['ecg_id']:>8} "
            f"{int(rec['age']):>4} "
            f"{rec['sex']:>4} "
            f"{rec['diagnosis']:>10} "
            f"{f['heart_rate_bpm']:>6} "
            f"{f['n_channels']:>9} "
            f"{f['duration_sec']:>8.1f}s "
            f"{f['confidence']:>11.2f} "
            f"{result['review_level']:>20}"
        )
    except Exception as e:
        errors.append({"ecg_id": rec["ecg_id"], "error": str(e)})
        print(f"{rec['ecg_id']:>8} ✗ ERROR: {e}")

print("─" * 95)
print(f"\n✓ Processed: {len(results)}/{len(records)} ECGs successfully")
if errors:
    print(f"✗ Errors:    {len(errors)}")

# Summary stats
if results:
    durations = [r["pipeline_result"]["findings"]["duration_sec"] for r in results]
    channels  = [r["pipeline_result"]["findings"]["n_channels"] for r in results]
    print(f"\nSignal stats:")
    print(f"  Duration : min={min(durations):.1f}s  max={max(durations):.1f}s  avg={sum(durations)/len(durations):.1f}s")
    print(f"  Channels : {set(channels)}")
    print(f"\nTrue diagnoses in sample:")
    dx_counts = {}
    for r in results:
        dx = r["diagnosis"]
        dx_counts[dx] = dx_counts.get(dx, 0) + 1
    for dx, count in sorted(dx_counts.items(), key=lambda x: -x[1]):
        print(f"  {dx:>10} : {'█' * count} ({count})")

print("\nNote: HR=72 and Confidence=0.87 are heuristic placeholders.")
print("Next step: connect ONNX classifier to get real per-record predictions.")
