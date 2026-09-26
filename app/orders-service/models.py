import uuid

from flask_sqlalchemy import SQLAlchemy
from sqlalchemy import CheckConstraint

db = SQLAlchemy()


class Order(db.Model):
    __tablename__ = "orders"
    __table_args__ = (
        CheckConstraint("quantity > 0", name="orders_quantity_positive"),
    )

    order_id = db.Column(db.String(36), primary_key=True, default=lambda: str(uuid.uuid4()))
    owner_username = db.Column(db.String(50), nullable=False)
    item = db.Column(db.String(255), nullable=False)
    quantity = db.Column(db.Integer, nullable=False, default=1)
    status = db.Column(db.String(20), nullable=False, default="created")