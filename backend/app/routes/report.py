from datetime import datetime, timedelta
from typing import Optional

from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session

from ..database import get_db
from ..models.user import User, UserRole
from ..models.sale import Sale, SaleItem
from ..models.damage_report import DamageReport
from ..models.product import Product
from ..models.stock_movement import StockMovement
from ..security import require_bos

router = APIRouter(prefix="/reports", tags=["reports"])


def get_sales_in_range(db: Session, start, end):
    if end is None:
        end = datetime.now()
    return db.query(Sale).filter(
        Sale.created_at >= start,
        Sale.created_at <= end,
        Sale.status == "COMPLETED",
    ).all()


def parse_date(date_str: Optional[str], default):
    if not date_str:
        return default
    try:
        return datetime.strptime(date_str, "%Y-%m-%d")
    except ValueError:
        raise HTTPException(status_code=400, detail="Format tanggal salah (YYYY-MM-DD)")


@router.get("/daily")
def daily_report(
    current_user: User = Depends(require_bos()),
    db: Session = Depends(get_db),
    date_str: Optional[str] = None,
):
    if date_str:
        date_obj = parse_date(date_str, datetime.now()).date()
        today = datetime.combine(date_obj, datetime.min.time())
    else:
        today = datetime.now().replace(hour=0, minute=0, second=0, microsecond=0)
    end = today + timedelta(days=1)
    sales = get_sales_in_range(db, today, end)
    total_amount = sum(float(s.total_amount) for s in sales)
    total_profit = sum(float(s.total_profit) for s in sales)
    item_count = sum(len(s.sale_items) for s in sales)
    return {
        "date": today.date().isoformat(),
        "total_sales": len(sales),
        "total_amount": round(total_amount, 2),
        "total_profit": round(total_profit, 2),
        "total_items": item_count,
        "sales": [s.to_dict() for s in sales],
    }


@router.get("/weekly")
def weekly_report(
    current_user: User = Depends(require_bos()),
    db: Session = Depends(get_db),
    date_str: Optional[str] = None,
):
    today = parse_date(date_str, datetime.now()).date()
    start = datetime.combine(today - timedelta(days=today.weekday()), datetime.min.time())
    end = start + timedelta(days=7)
    sales = get_sales_in_range(db, start, end)
    return {
        "start": start.date().isoformat(),
        "end": (end - timedelta(seconds=1)).date().isoformat(),
        "total_sales": len(sales),
        "total_amount": round(sum(float(s.total_amount) for s in sales), 2),
        "total_profit": round(sum(float(s.total_profit) for s in sales), 2),
    }


@router.get("/monthly")
def monthly_report(
    current_user: User = Depends(require_bos()),
    db: Session = Depends(get_db),
    month: Optional[str] = None,
):
    if month:
        try:
            year, m = month.split("-")
            start = datetime(int(year), int(m), 1)
        except Exception:
            raise HTTPException(status_code=400, detail="Format bulan salah (YYYY-MM)")
    else:
        now = datetime.now()
        start = datetime(now.year, now.month, 1)
    if start.month == 12:
        end = datetime(start.year + 1, 1, 1)
    else:
        end = datetime(start.year, start.month + 1, 1)
    sales = get_sales_in_range(db, start, end)
    return {
        "month": start.strftime("%Y-%m"),
        "total_sales": len(sales),
        "total_amount": round(sum(float(s.total_amount) for s in sales), 2),
        "total_profit": round(sum(float(s.total_profit) for s in sales), 2),
    }


@router.get("/top-products")
def top_products(
    current_user: User = Depends(require_bos()),
    db: Session = Depends(get_db),
    limit: int = 10,
):
    from sqlalchemy import func
    rows = (
        db.query(
            SaleItem.product_id,
            Product.name.label("product_name"),
            func.sum(SaleItem.quantity).label("total_qty"),
            func.sum(SaleItem.subtotal).label("total_revenue"),
        )
        .join(Product, SaleItem.product_id == Product.id)
        .group_by(SaleItem.product_id, Product.name)
        .order_by(func.sum(SaleItem.quantity).desc())
        .limit(limit)
        .all()
    )
    return [
        {
            "product_id": str(r.product_id),
            "product_name": r.product_name,
            "total_qty": round(float(r.total_qty), 3),
            "total_revenue": round(float(r.total_revenue), 2),
        }
        for r in rows
    ]


@router.get("/by-employee")
def sales_by_employee(
    current_user: User = Depends(require_bos()),
    db: Session = Depends(get_db),
    date_from: Optional[str] = None,
    date_to: Optional[str] = None,
):
    query = db.query(Sale).filter(Sale.status == "COMPLETED")
    if date_from:
        query = query.filter(Sale.created_at >= date_from)
    if date_to:
        query = query.filter(Sale.created_at <= f"{date_to} 23:59:59")
    sales = query.all()

    from collections import defaultdict
    by_emp = defaultdict(lambda: {"count": 0, "amount": 0.0, "profit": 0.0})
    for s in sales:
        emp_id = str(s.employee_id)
        emp_name = s.employee.full_name if s.employee else "?"
        by_emp[emp_id]["count"] += 1
        by_emp[emp_id]["amount"] += float(s.total_amount)
        by_emp[emp_id]["profit"] += float(s.total_profit)
        by_emp[emp_id]["name"] = emp_name

    return [
        {
            "employee_id": k,
            "employee_name": v["name"],
            "total_sales": v["count"],
            "total_amount": round(v["amount"], 2),
            "total_profit": round(v["profit"], 2),
        }
        for k, v in by_emp.items()
    ]


@router.get("/damage")
def damage_report_summary(
    current_user: User = Depends(require_bos()),
    db: Session = Depends(get_db),
    date_from: Optional[str] = None,
    date_to: Optional[str] = None,
):
    query = db.query(DamageReport)
    if date_from:
        query = query.filter(DamageReport.created_at >= date_from)
    if date_to:
        query = query.filter(DamageReport.created_at <= f"{date_to} 23:59:59")
    reports = query.all()

    total_approved_qty = 0
    total_loss_value = 0.0
    per_product = {}
    status_counts = {"PENDING": 0, "APPROVED": 0, "REJECTED": 0}

    for r in reports:
        status_counts[r.status] = status_counts.get(r.status, 0) + 1
        if r.status == "APPROVED":
            total_approved_qty += float(r.quantity)
            modal = float(r.product.modal_price or 0) if r.product else 0
            loss = modal * float(r.quantity)
            total_loss_value += loss
            key = r.product.name if r.product else "?"
            if key not in per_product:
                per_product[key] = {"quantity": 0, "loss_value": 0}
            per_product[key]["quantity"] += float(r.quantity)
            per_product[key]["loss_value"] += loss

    return {
        "total_reports": len(reports),
        "status_counts": status_counts,
        "total_approved_quantity": round(total_approved_qty, 3),
        "total_loss_value": round(total_loss_value, 2),
        "per_product": per_product,
    }


@router.get("/dashboard")
def dashboard(
    current_user: User = Depends(require_bos()),
    db: Session = Depends(get_db),
):
    now = datetime.now()
    today_start = now.replace(hour=0, minute=0, second=0, microsecond=0)
    today_end = today_start + timedelta(days=1)

    today_sales = get_sales_in_range(db, today_start, today_end)
    revenue_today = sum(float(s.total_amount) for s in today_sales)
    profit_today = sum(float(s.total_profit) for s in today_sales)
    items_sold = sum(len(s.sale_items) for s in today_sales)

    pending_damage = db.query(DamageReport).filter(
        DamageReport.status == "PENDING"
    ).all()

    damage_loss_value = 0.0
    for d in pending_damage:
        damage_loss_value += float(d.quantity) * float(d.product.modal_price or 0) if d.product else 0

    low_stock = [
        p.to_dict()
        for p in db.query(Product).filter(Product.is_active == True).all()
        if float(p.stock or 0) <= float(p.min_stock or 0)
    ]

    from sqlalchemy import func
    top_products_rows = (
        db.query(
            SaleItem.product_id,
            Product.name.label("product_name"),
            func.sum(SaleItem.quantity).label("total_qty"),
        )
        .join(Product, SaleItem.product_id == Product.id)
        .join(Sale, SaleItem.sale_id == Sale.id)
        .filter(Sale.created_at >= today_start, Sale.created_at <= today_end, Sale.status == "COMPLETED")
        .group_by(SaleItem.product_id, Product.name)
        .order_by(func.sum(SaleItem.quantity).desc())
        .limit(5)
        .all()
    )
    top_products = [
        {"product_id": str(r.product_id), "name": r.product_name, "total_qty": round(float(r.total_qty), 3)}
        for r in top_products_rows
    ]

    by_employee_rows = db.query(
        Sale.employee_id, User.full_name,
        func.count(Sale.id).label("count"),
        func.sum(Sale.total_amount).label("amount"),
    ).join(User, Sale.employee_id == User.id).filter(
        Sale.created_at >= today_start, Sale.created_at <= today_end, Sale.status == "COMPLETED"
    ).group_by(Sale.employee_id, User.full_name).all()

    by_employee = [
        {"employee_id": str(r.employee_id), "name": r.full_name, "count": r.count, "amount": round(float(r.amount or 0), 2)}
        for r in by_employee_rows
    ]

    return {
        "revenue_today": round(revenue_today, 2),
        "sales_count_today": len(today_sales),
        "items_sold_today": items_sold,
        "profit_today": round(profit_today, 2),
        "pending_damage_count": len(pending_damage),
        "pending_damage_loss_value": round(damage_loss_value, 2),
        "low_stock_products": low_stock,
        "top_products": top_products,
        "sales_by_employee": by_employee,
    }


@router.get("/stock")
def stock_report(
    current_user: User = Depends(require_bos()),
    db: Session = Depends(get_db),
    date_from: Optional[str] = None,
    date_to: Optional[str] = None,
):
    """Laporan stok masuk/keluar dan sisa stok per produk."""
    movements = db.query(StockMovement)
    if date_from:
        movements = movements.filter(StockMovement.created_at >= date_from)
    if date_to:
        movements = movements.filter(StockMovement.created_at <= f"{date_to} 23:59:59")
    movement_rows = movements.order_by(StockMovement.created_at.desc()).all()

    from collections import defaultdict
    per_product = defaultdict(lambda: {
        "stock_in": 0.0,
        "sale_out": 0.0,
        "damage_out": 0.0,
        "return_in": 0.0,
        "adjustment": 0.0,
        "name": None,
    })
    for m in movement_rows:
        p = db.query(Product).filter(Product.id == m.product_id).first()
        key = str(m.product_id)
        per_product[key]["name"] = p.name if p else m.product_id
        qty = float(m.quantity)
        t = m.movement_type
        if t == "STOCK_IN":
            per_product[key]["stock_in"] += qty
        elif t == "SALE":
            per_product[key]["sale_out"] += qty
        elif t == "DAMAGE":
            per_product[key]["damage_out"] += qty
        elif t == "RETURN":
            per_product[key]["return_in"] += qty
        elif t in ("ADJUSTMENT", "ADJUSTMENT_NEGATIVE"):
            per_product[key]["adjustment"] += qty if t == "ADJUSTMENT" else -qty

    products = db.query(Product).all()
    current_stock = {str(p.id): p for p in products}

    result = []
    for product_id, d in per_product.items():
        p = current_stock.get(product_id)
        result.append({
            "product_id": product_id,
            "product_name": d["name"],
            "stock_in": round(d["stock_in"], 3),
            "sale_out": round(d["sale_out"], 3),
            "damage_out": round(d["damage_out"], 3),
            "return_in": round(d["return_in"], 3),
            "adjustment": round(d["adjustment"], 3),
            "current_stock": round(float(p.stock or 0), 3) if p else 0,
        })

    total_stock_in = sum(r["stock_in"] for r in result)
    total_sale_out = sum(r["sale_out"] for r in result)
    total_damage = sum(r["damage_out"] for r in result)
    return {
        "date_from": date_from,
        "date_to": date_to,
        "products": result,
        "totals": {
            "stock_in": round(total_stock_in, 3),
            "sale_out": round(total_sale_out, 3),
            "damage": round(total_damage, 3),
        },
        "low_stock": [p.to_dict() for p in products if float(p.stock or 0) <= float(p.min_stock or 0)],
    }


@router.get("/profit")
def profit_report(
    current_user: User = Depends(require_bos()),
    db: Session = Depends(get_db),
    date_from: Optional[str] = None,
    date_to: Optional[str] = None,
):
    """Laporan laba kotor & kerugian waste untuk periode tertentu."""
    sales_q = db.query(Sale).filter(Sale.status == "COMPLETED")
    if date_from:
        sales_q = sales_q.filter(Sale.created_at >= date_from)
    if date_to:
        sales_q = sales_q.filter(Sale.created_at <= f"{date_to} 23:59:59")
    sales = sales_q.all()

    total_revenue = sum(float(s.total_amount) for s in sales)
    total_modal = sum(float(s.total_modal) for s in sales)
    total_profit = total_revenue - total_modal
    total_discount = sum(float(s.discount) for s in sales)
    sales_count = len(sales)

    damage_q = db.query(DamageReport).filter(DamageReport.status == "APPROVED")
    if date_from:
        damage_q = damage_q.filter(DamageReport.created_at >= date_from)
    if date_to:
        damage_q = damage_q.filter(DamageReport.created_at <= f"{date_to} 23:59:59")
    damages = damage_q.all()

    total_damage_loss = 0.0
    total_damage_qty = 0.0
    for d in damages:
        modal = float(d.product.modal_price or 0) if d.product else 0
        total_damage_loss += modal * float(d.quantity)
        total_damage_qty += float(d.quantity)

    net_profit = total_profit - total_damage_loss

    return {
        "date_from": date_from,
        "date_to": date_to,
        "total_revenue": round(total_revenue, 2),
        "total_modal": round(total_modal, 2),
        "total_profit_gross": round(total_profit, 2),
        "total_discount": round(total_discount, 2),
        "sales_count": sales_count,
        "damage_quantity": round(total_damage_qty, 3),
        "damage_loss": round(total_damage_loss, 2),
        "net_profit": round(net_profit, 2),
        "gross_margin_percent": round((total_profit / total_revenue * 100), 2) if total_revenue else 0,
    }