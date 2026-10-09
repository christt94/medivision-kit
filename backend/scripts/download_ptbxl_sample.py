import urllib.request, pandas as pd, wfdb, os, json, shutil

SAMPLE_DIR = "data/samples/ptbxl"
TMP_DIR = f"{SAMPLE_DIR}/tmp"
os.makedirs(SAMPLE_DIR, exist_ok=True)
os.makedirs(TMP_DIR, exist_ok=True)
BASE_URL = "https://physionet.org/files/ptb-xl/1.0.3"

df = pd.read_csv(f"{SAMPLE_DIR}/ptbxl_database.csv", index_col="ecg_id")
df["scp_codes"] = df["scp_codes"].apply(lambda x: json.loads(x.replace("'", '"')))

downloaded = []
print(f"Downloading 10 ECG records...")

for ecg_id, row in df.head(10).iterrows():
    rpath = row["filename_lr"]          # e.g. records100/00000/00001_lr
    basename = os.path.basename(rpath)  # e.g. 00001_lr

    hea_local = f"{TMP_DIR}/{basename}.hea"
    dat_local = f"{TMP_DIR}/{basename}.dat"

    try:
        urllib.request.urlretrieve(f"{BASE_URL}/{rpath}.hea", hea_local)
        urllib.request.urlretrieve(f"{BASE_URL}/{rpath}.dat", dat_local)

        # Read from tmp dir using exact basename (no extension)
        record = wfdb.rdrecord(f"{TMP_DIR}/{basename}")

        signal = record.p_signal  # (n_samples, n_channels)
        out = f"{SAMPLE_DIR}/ecg_{ecg_id:05d}.csv"
        pd.DataFrame(signal, columns=record.sig_name).to_csv(out, index=False)

        # Cleanup tmp files
        os.remove(hea_local)
        os.remove(dat_local)

        scp = row["scp_codes"]
        dominant = max(scp, key=scp.get) if scp else "UNKNOWN"
        age = float(row["age"]) if pd.notna(row["age"]) else 0
        sex = "M" if row["sex"] == 0 else "F"

        downloaded.append({
            "ecg_id": int(ecg_id), "file": out, "age": age, "sex": sex,
            "diagnosis": dominant, "scp_codes": scp,
            "n_samples": signal.shape[0], "n_channels": signal.shape[1],
            "sampling_rate": record.fs
        })
        print(f"  ✓ ECG {ecg_id:05d} | {int(age):>3}y {sex} | {dominant} | {signal.shape[0]} samples")
    except Exception as e:
        print(f"  ✗ ECG {ecg_id:05d} | {e}")

shutil.rmtree(TMP_DIR, ignore_errors=True)

with open(f"{SAMPLE_DIR}/manifest.json", "w") as f:
    json.dump(downloaded, f, indent=2)

print(f"\n✓ {len(downloaded)}/10 ECGs saved to {SAMPLE_DIR}/")
if downloaded:
    print("\nDiagnoses:")
    for r in downloaded:
        print(f"  ECG {r['ecg_id']:05d} | {int(r['age']):>3}y {r['sex']} | {r['diagnosis']}")
