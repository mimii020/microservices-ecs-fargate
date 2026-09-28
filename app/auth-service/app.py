import os
import uuid
import hashlib
from datetime import datetime, timedelta

from flask import Flask, Blueprint, request, jsonify

from models import db, User

app = Flask(__name__)
auth = Blueprint("auth", __name__)

app.config["SQLALCHEMY_DATABASE_URI"] = (
    f"postgresql://{os.environ['DB_USERNAME']}:{os.environ['DB_PASSWORD']}"
    f"@{os.environ['DB_HOST']}:{os.environ['DB_PORT']}/{os.environ['DB_NAME']}"
)
app.config["SQLALCHEMY_TRACK_MODIFICATIONS"] = False
db.init_app(app)

with app.app_context():
    db.create_all()

TOKENS = {}
TOKEN_TTL_MINUTES = 60


def hash_password(password: str) -> str:
    return hashlib.sha256(password.encode()).hexdigest()


@auth.route("/health", methods=["GET"])
def health():
    return jsonify(status="ok", service="auth"), 200


@auth.route("/register", methods=["POST"])
def register():
    data = request.get_json(force=True)
    username = data.get("username")
    password = data.get("password")

    if not username or not password:
        return jsonify(error="username and password required"), 400

    if User.query.filter_by(username=username).first():
        return jsonify(error="user already exists"), 409

    user = User(username=username, password_hash=hash_password(password))
    db.session.add(user)
    db.session.commit()

    return jsonify(message="user registered", username=username), 201


@auth.route("/login", methods=["POST"])
def login():
    data = request.get_json(force=True)
    username = data.get("username")
    password = data.get("password")

    user = User.query.filter_by(username=username).first()
    if not user or user.password_hash != hash_password(password or ""):
        return jsonify(error="invalid credentials"), 401

    token = str(uuid.uuid4())
    TOKENS[token] = {
        "username": username,
        "expires": datetime.utcnow() + timedelta(minutes=TOKEN_TTL_MINUTES),
    }
    return jsonify(token=token, expires_in_minutes=TOKEN_TTL_MINUTES), 200


@auth.route("/verify", methods=["GET"])
def verify():
    token = request.headers.get("Authorization", "").replace("Bearer ", "")
    entry = TOKENS.get(token)

    if not entry or entry["expires"] < datetime.utcnow():
        return jsonify(valid=False), 401
    return jsonify(valid=True, username=entry["username"]), 200


app.register_blueprint(auth, url_prefix="/auth")

if __name__ == "__main__":
    port = int(os.environ.get("PORT", 5000))
    app.run(host="0.0.0.0", port=port)