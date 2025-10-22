import os
import requests

# Türkiye sınırları için tahmini tile aralığı (zoom 5-12)
ZOOM_LEVELS = range(5, 13)
X_RANGE = {
    5: range(27, 33),
    6: range(54, 65),
    7: range(108, 130),
    8: range(217, 261),
    9: range(435, 523),
    10: range(870, 1047),
    11: range(1740, 2094),
    12: range(3480, 4188),
}
Y_RANGE = {
    5: range(18, 23),
    6: range(36, 46),
    7: range(73, 92),
    8: range(146, 185),
    9: range(292, 370),
    10: range(584, 739),
    11: range(1168, 1478),
    12: range(2336, 2956),
}

def download_tiles():
    for z in ZOOM_LEVELS:
        for x in X_RANGE[z]:
            for y in Y_RANGE[z]:
                url = f"https://tile.openstreetmap.org/{z}/{x}/{y}.png"
                folder = f"assets/tiles/{z}/{x}"
                os.makedirs(folder, exist_ok=True)
                file_path = f"{folder}/{y}.png"
                if not os.path.exists(file_path):
                    try:
                        r = requests.get(url, timeout=10)
                        if r.status_code == 200:
                            with open(file_path, 'wb') as f:
                                f.write(r.content)
                            print(f"Downloaded {file_path}")
                        else:
                            print(f"Skipped {file_path}: Invalid tile or not found (status {r.status_code})")
                    except Exception as e:
                        print(f"Failed {file_path}: {e}")

if __name__ == "__main__":
    download_tiles()
