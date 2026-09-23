import os
import uuid
import hashlib
from datetime import datetime, timedelta

from flask import Flask, request, jsonify

app = Flask(__name__)

USERS = {}
TOKENS = {}

TOKEN_TTL_MINUTES = 60


def hash_password(password: str) -> str:
    return hashlib.sha256(password.encode()).hexdigest()


@app.route("/health", methods=["GET"])
def health():
    return jsonify(status="ok", service="auth"), 200


@app.route("/register", methods=["POST"])
def register():
    data = request.get_json(force=True)
    username = data.get("username")
    password = data.get("password")

    if not username or not password:
        return jsonify(error="username and password required"), 400
    if username in USERS:
        return jsonify(error="user already exists"), 409

    USERS[username] = hash_password(password)
    return jsonify(message="user registered", username=username), 201


@app.route("/login", methods=["POST"])
def login():
    data = request.get_json(force=True)
    username = data.get("username")
    password = data.get("password")

    if USERS.get(username) != hash_password(password or ""):
        return jsonify(error="invalid credentials"), 401

    token = str(uuid.uuid4())
    TOKENS[token] = {
        "username": username,
        "expires": datetime.utcnow() + timedelta(minutes=TOKEN_TTL_MINUTES),
    }
    return jsonify(token=token, expires_in_minutes=TOKEN_TTL_MINUTES), 200


@app.route("/verify", methods=["GET"])
def verify():
    token = request.headers.get("Authorization", "").replace("Bearer ", "")
    entry = TOKENS.get(token)

    if not entry or entry["expires"] < datetime.utcnow():
        return jsonify(valid=False), 401

    return jsonify(valid=True, username=entry["username"]), 200


if __name__ == "__main__":
    port = int(os.environ.get("PORT", 5000))
    app.run(host="0.0.0.0", port=port)