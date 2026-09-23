import os
import uuid

import requests
from flask import Flask, request, jsonify

app = Flask(__name__)

ORDERS = {}

AUTH_SERVICE_URL = os.environ.get("AUTH_SERVICE_URL", "http://localhost:5000")


def get_authenticated_user():
    """Calls the auth service to validate the bearer token on this request."""
    auth_header = request.headers.get("Authorization", "")
    try:
        resp = requests.get(
            f"{AUTH_SERVICE_URL}/verify",
            headers={"Authorization": auth_header},
            timeout=3,
        )
    except requests.RequestException:
        return None

    if resp.status_code != 200:
        return None
    return resp.json().get("username")


@app.route("/health", methods=["GET"])
def health():
    return jsonify(status="ok", service="orders"), 200


@app.route("/orders", methods=["POST"])
def create_order():
    username = get_authenticated_user()
    if not username:
        return jsonify(error="unauthorized"), 401

    data = request.get_json(force=True)
    item = data.get("item")
    quantity = data.get("quantity", 1)

    if not item:
        return jsonify(error="item is required"), 400

    order_id = str(uuid.uuid4())
    ORDERS[order_id] = {
        "id": order_id,
        "owner": username,
        "item": item,
        "quantity": quantity,
        "status": "created",
    }
    return jsonify(ORDERS[order_id]), 201


@app.route("/orders", methods=["GET"])
def list_orders():
    username = get_authenticated_user()
    if not username:
        return jsonify(error="unauthorized"), 401

    mine = [o for o in ORDERS.values() if o["owner"] == username]
    return jsonify(orders=mine), 200


@app.route("/orders/<order_id>", methods=["GET"])
def get_order(order_id):
    username = get_authenticated_user()
    if not username:
        return jsonify(error="unauthorized"), 401

    order = ORDERS.get(order_id)
    if not order or order["owner"] != username:
        return jsonify(error="order not found"), 404

    return jsonify(order), 200


if __name__ == "__main__":
    port = int(os.environ.get("PORT", 5001))
    app.run(host="0.0.0.0", port=port)