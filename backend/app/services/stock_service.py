from datetime import datetime
from sqlalchemy.orm import Session

from ..models.stock_movement import StockMovement
from ..models.product import Product
from ..models.user import User


class InsufficientStockError(Exception):
    pass


# ----- Konversi satuan untuk laporan kerusakan -----
# Massa (gram sebagai basis)
_UNIT_MASS_GRAMS = {"kg": 1000.0, "gram": 1.0}
# Satuan hitung yang setara 1:1 (buah = pcs)
_UNIT_COUNT = {"buah", "pcs"}


def convert_quantity(value, from_unit, to_unit):
    """Konversi kuantitas antar satuan. None jika kombinasi tidak dikenal."""
    f = (from_unit or "").strip().lower()
    t = (to_unit or "").strip().lower()
    if not value or value <= 0:
        return 0.0
    if f == t:
        return value
    if f in _UNIT_MASS_GRAMS and t in _UNIT_MASS_GRAMS:
        return round(value * _UNIT_MASS_GRAMS[f] / _UNIT_MASS_GRAMS[t], 4)
    if f in _UNIT_COUNT and t in _UNIT_COUNT:
        return round(value, 4)
    return None


def record_stock_movement(
    db: Session,
    product: Product,
    movement_type: str,
    quantity: float,
    user: User,
    reference_id=None,
    reference_type=None,
    notes=None,
) -> StockMovement:
    stock_before = float(product.stock or 0)
    if movement_type in ("SALE", "DAMAGE", "ADJUSTMENT_NEGATIVE", "RETURN_OUT"):
        stock_after = stock_before - quantity
        if stock_after < 0:
            raise InsufficientStockError(
                f"Stok tidak mencukupi. Tersedia {stock_before}, diminta {quantity}"
            )
    else:
        stock_after = stock_before + quantity

    product.stock = stock_after

    movement = StockMovement(
        product_id=product.id,
        movement_type=movement_type,
        quantity=quantity,
        stock_before=stock_before,
        stock_after=stock_after,
        reference_id=reference_id,
        reference_type=reference_type,
        notes=notes,
        user_id=user.id,
        created_at=datetime.utcnow(),
    )
    db.add(movement)
    db.commit()
    db.refresh(movement)
    return movement


def record_stock_in(
    db: Session,
    product: Product,
    reference_id,
    quantity: float,
    user: User,
    movement_type: str = "STOCK_IN",
    notes=None,
) -> StockMovement:
    return record_stock_movement(
        db, product, movement_type, quantity, user,
        reference_id=reference_id, reference_type="stock_in", notes=notes,
    )


def record_sale_quantity(
    db: Session,
    product: Product,
    sale_id,
    quantity: float,
    user: User,
) -> StockMovement:
    return record_stock_movement(
        db, product, "SALE", quantity, user,
        reference_id=sale_id, reference_type="sale",
        notes=f"Penjualan produk {product.name}",
    )


def record_damage(
    db: Session,
    product: Product,
    damage_report_id,
    quantity: float,
    user: User,
) -> StockMovement:
    return record_stock_movement(
        db, product, "DAMAGE", quantity, user,
        reference_id=damage_report_id, reference_type="damage_report",
        notes=f"Produk rusak: laporan {damage_report_id}",
    )


def record_stock_adjustment(
    db: Session,
    product: Product,
    quantity: float,
    user: User,
    notes=None,
) -> StockMovement:
    movement_type = "ADJUSTMENT" if quantity >= 0 else "ADJUSTMENT_NEGATIVE"
    return record_stock_movement(
        db, product, movement_type, abs(quantity), user,
        reference_type="adjustment", notes=notes,
    )