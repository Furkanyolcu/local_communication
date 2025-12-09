import tensorflow as tf
from flask import Flask, request, jsonify
from flask_cors import CORS
import requests
import numpy as np
from PIL import Image
import io
import os

MODEL_URL = "https://disaster-ai-models.obs.ap-southeast-1.myhuaweicloud.com/1/model.h5"
MODEL_PATH = "model.h5"
# Eğitimde kullanılan sınıf kodları: 1=hasarlı, 2=yıkılmış, 3=hasarsız
CLASS_NAMES = ["hasarlı", "yıkılmış", "hasarsız"]  # indeks 0->1, 1->2, 2->3
CLASS_CODES = [1, 2, 3]
app = Flask(__name__)
# CORS: Flutter Web'den gelen istekleri kabul et
CORS(app, resources={r"/*": {"origins": "*"}}, supports_credentials=True)

# -----------------------------------
# MODEL İNDİRME
# -----------------------------------
def _is_valid_h5(path: str) -> bool:
    try:
        with open(path, "rb") as f:
            sig = f.read(8)
        return sig == b"\x89HDF\r\n\x1a\n"
    except Exception:
        return False

def download_model():
    """Model dosyasını güvenli şekilde indir ve doğrula."""
    try:
        if not os.path.exists(MODEL_PATH):
            print("Model indiriliyor...")
            r = requests.get(MODEL_URL, stream=True, timeout=60)
            r.raise_for_status()

            # İçerik türünü ve boyutu kontrol et
            content_type = r.headers.get("Content-Type", "")
            content_length = r.headers.get("Content-Length")

            # H5 dosyası olduğunu garanti edemeyiz; imza kontrolü yapacağız
            # HDF5 dosya imzası: 0x89 0x48 0x44 0x46 0x0d 0x0a 0x1a 0x0a
            h5_signature = b"\x89HDF\r\n\x1a\n"

            # İlk baytları oku ve imzayı doğrula
            head = r.raw.read(8)
            if head != h5_signature:
                # Muhtemel HTML hata sayfası veya farklı format
                # Kalan içeriği yine de diske yazmadan önce akışı tüketip hatayı raporla
                print("Uyarı: İndirilen dosya HDF5 imzası taşımıyor. İçerik tipi:", content_type)
                # İndirilen dosya geçersiz; kullanıcıya anlaşılır bilgi ver ve yüklemeyi durdur
                raise OSError("Geçersiz model dosyası (HDF5 imzası bulunamadı). Kaynak URL yanlış veya erişim engellendi olabilir.")

            # İmzayı ve geri kalan içeriği dosyaya yaz
            with open(MODEL_PATH, "wb") as f:
                f.write(head)
                for chunk in r.iter_content(chunk_size=1024 * 1024):
                    if chunk:
                        f.write(chunk)

            size_str = f"{os.path.getsize(MODEL_PATH)} bayt"
            print("Model indirildi! Boyut:", size_str)
        else:
            # Mevcut dosya geçerli mi, kontrol et; değilse yeniden indir
            if _is_valid_h5(MODEL_PATH):
                print("Model zaten mevcut.")
            else:
                print("Mevcut model dosyası geçersiz, yeniden indiriliyor...")
                os.remove(MODEL_PATH)
                r = requests.get(MODEL_URL, stream=True, timeout=60)
                r.raise_for_status()
                h5_signature = b"\x89HDF\r\n\x1a\n"
                head = r.raw.read(8)
                if head != h5_signature:
                    raise OSError("Geçersiz model dosyası (HDF5 imzası bulunamadı).")
                with open(MODEL_PATH, "wb") as f:
                    f.write(head)
                    for chunk in r.iter_content(chunk_size=1024 * 1024):
                        if chunk:
                            f.write(chunk)
                print("Model indirildi! Boyut:", f"{os.path.getsize(MODEL_PATH)} bayt")
    except Exception as e:
        # Geçersiz kısmi dosya kalmışsa sil
        if os.path.exists(MODEL_PATH):
            try:
                os.remove(MODEL_PATH)
            except Exception:
                pass
        print("Model indirme hatası:", e)
        # Uygulamayı anlamlı bir mesajla sonlandır
        raise SystemExit("Model indirilemedi veya doğrulanamadı. Lütfen MODEL_URL kontrol edin.")

download_model()

# Model yükleme
try:
    model = tf.keras.models.load_model(MODEL_PATH)
    print("Model yüklendi!")
except Exception as e:
    print("Model yükleme hatası:", e)
    raise SystemExit("Model dosyası bozuk veya uyumsuz. İndirme kaynağını kontrol edin.")

# -----------------------------------
# ÖN İŞLEME & TAHMİN
# -----------------------------------
def preprocess_image(image_bytes):
    img = Image.open(io.BytesIO(image_bytes)).convert("RGB")
    img = img.resize((224, 224))            # modele göre ayarlanabilir
    img = np.array(img) / 255.0
    img = np.expand_dims(img, axis=0)
    return img

# -----------------------------------
# API - POST /predict
# -----------------------------------
@app.route("/predict", methods=["POST"])
def predict():
    # Önce multipart/form-data içindeki 'file' anahtarını dene
    image_bytes = None
    if 'file' in request.files:
        image_bytes = request.files['file'].read()
    else:
        # Raw body (application/octet-stream veya image/*) olarak gönderilmiş olabilir
        ct = request.headers.get('Content-Type', '')
        if ct.startswith('image/') or ct.startswith('application/octet-stream'):
            image_bytes = request.get_data()

    if not image_bytes:
        return jsonify({
            "error": "Geçersiz istek. 'file' (multipart/form-data) gönderin veya body'yi raw binary olarak image/* / application/octet-stream içerik türüyle sağlayın."
        }), 400

    img = preprocess_image(image_bytes)
    preds = model.predict(img)[0]  # shape: (3,)

    # Yapılandırılmış çıktı: eğitimdeki kodlarla (1,2,3) eşleştir
    detailed = [
        {
            "code": CLASS_CODES[i],
            "label": CLASS_NAMES[i],
            "score": float(preds[i])
        }
        for i in range(len(CLASS_CODES))
    ]

    top_idx = int(np.argmax(preds))
    top1 = {
        "code": CLASS_CODES[top_idx],
        "label": CLASS_NAMES[top_idx],
        "score": float(preds[top_idx])
    }

    resp = jsonify({
        "prediction": detailed,
        "top1": top1
    })
    # Ek CORS header'ları (bazı ortamlarda gerekli olabilir)
    resp.headers["Access-Control-Allow-Origin"] = "*"
    resp.headers["Access-Control-Allow-Headers"] = "*"
    resp.headers["Access-Control-Allow-Methods"] = "POST, OPTIONS"
    return resp


# -----------------------------------
# Server başlat
# -----------------------------------
if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5000, debug=True)
