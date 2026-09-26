import os

import requests
from flask import Flask, Blueprint, request, jsonify

from models import db, Order

app = Flask(__name__)
orders = Blueprint("orders", __name__)

app.config["SQLALCHEMY_DATABASE_URI"] = (
    f"postgresql://{os.environ['DB_USERNAME']}:{os.environ['DB_PASSWORD']}"
    f"@{os.environ['DB_HOST']}:{os.environ['DB_PORT']}/{os.environ['DB_NAME']}"
)
app.config["SQLALCHEMY_TRACK_MODIFICATIONS"] = False
db.init_app(app)

with app.app_context():
    db.create_all()

AUTH_SERVICE_URL = os.environ.get("AUTH_SERVICE_URL", "http://localhost:5000")


def get_authenticated_user():
    """Calls the auth service to validate the bearer token on this request."""
    auth_header = request.headers.get("Authorization", "")
    try:
        resp = requests.get(
            f"{AUTH_SERVICE_URL}/auth/verify",
            headers={"Authorization": auth_header},
            timeout=3,
        )
    except requests.RequestException:
        return None

    if resp.status_code != 200:
        return None
    return resp.json().get("username")


def order_to_dict(order: Order) -> dict:
    return {
        "id": order.order_id,
        "owner": order.owner_username,
        "item": order.item,
        "quantity": order.quantity,
        "status": order.status,
    }


@app.route("/health", methods=["GET"])
def health():
    return jsonify(status="ok", service="orders"), 200


@orders.route("/", methods=["POST"])
def create_order():
    username = get_authenticated_user()
    if not username:
        return jsonify(error="unauthorized"), 401

    data = request.get_json(force=True)
    item = data.get("item")
    quantity = data.get("quantity", 1)

    if not item:
        return jsonify(error="item is required"), 400
    if not isinstance(quantity, int) or quantity <= 0:
        return jsonify(error="quantity must be a positive integer"), 400

    order = Order(owner_username=username, item=item, quantity=quantity)
    db.session.add(order)
    db.session.commit()

    return jsonify(order_to_dict(order)), 201


@orders.route("/", methods=["GET"])
def list_orders():
    username = get_authenticated_user()
    if not username:
        return jsonify(error="unauthorized"), 401

    mine = Order.query.filter_by(owner_username=username).all()
    return jsonify(orders=[order_to_dict(o) for o in mine]), 200


@orders.route("/<order_id>", methods=["GET"])
def get_order(order_id):
    username = get_authenticated_user()
    if not username:
        return jsonify(error="unauthorized"), 401

    order = Order.query.filter_by(order_id=order_id, owner_username=username).first()
    if not order:
        return jsonify(error="order not found"), 404

    return jsonify(order_to_dict(order)), 200


app.register_blueprint(orders, url_prefix="/orders")

if __name__ == "__main__":
    port = int(os.environ.get("PORT", 5001))
    app.run(host="0.0.0.0", port=port)