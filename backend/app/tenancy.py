"""Aturan multi-tenant: siapa boleh melihat baris toko yang mana.

Modul ini adalah SATU-SATUNYA tempat keputusan scope dibuat. Semua query
data toko wajib lewat sini, bukan memfilter manual di tiap route, supaya
tidak ada endpoint yang diam-diam lupa memfilter.

Prinsip:
  - Fail-closed. User toko tanpa store_id tidak boleh melihat apa pun.
  - Role OWNER adalah satu-satunya yang boleh melihat lintas-toko, dan
    tetap WAJIB menyebut store_id secara eksplisit saat administersi satu
    toko. Tidak ada "lihat semua" tanpa target yang disengaja.
"""
from typing import Optional
from uuid import UUID

from fastapi import HTTPException, status
from sqlalchemy.orm import Session, Query

from .models.user import User, UserRole


class ScopeError(HTTPException):
    """Akses ke data toko lain. 403, bukan 404, supaya Owner's log audit
    bisa membedakan 'tidak ada' dari 'dilarang'."""


def is_owner(user: Optional[User]) -> bool:
    return user is not None and user.role == UserRole.OWNER.value


def require_store_id(user: User) -> UUID:
    """Ambil store_id milik user. Gagal keras bila kosong.

    Guard terpenting: user toko yang somehow punya store_id NULL akan
    ditolak, bukan otomatis melihat semua toko.
    """
    if is_owner(user):
        raise ScopeError(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Endpoint ini per toko. Owner wajib menyebut store_id secara eksplisit.",
        )
    if user.store_id is None:
        raise ScopeError(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Akun ini belum tertaut ke toko. Hubungi pemilik layanan.",
        )
    return user.store_id


def store_filter(query: Query, model, user: User, store_id: Optional[UUID] = None) -> Query:
    """Batasi query ke toko user, atau ke store_id tertentu bila diberikan.

    store_id:
      - None : user toko -> filter ke tokonya.
               OWNER     -> tidak difilter, untuk agregasi lintas-toko
                             yang disengaja (mis. ringkasan dashboard).
                             Jangan pakai untuk serving data satu toko.
      - UUID : user toko -> WAJIB sama dengan tokonya, kalau tidak 403.
               OWNER     -> difilter ke toko itu saja.
    """
    if store_id is not None:
        if not is_owner(user):
            if user.store_id is None or user.store_id != store_id:
                raise ScopeError(
                    status_code=status.HTTP_403_FORBIDDEN,
                    detail="Toko tersebut bukan milik akun Anda",
                )
        return query.filter(model.store_id == store_id)

    if is_owner(user):
        return query

    return query.filter(model.store_id == require_store_id(user))


def assert_can_access_store(user: User, store_id: UUID) -> UUID:
    """Cegah akses silang pada operasi yang punya store_id dari body/path."""
    if is_owner(user):
        return store_id
    if user.store_id is None or user.store_id != store_id:
        raise ScopeError(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Toko tersebut bukan milik akun Anda",
        )
    return store_id


def ensure_not_owner_store(user: User, store_id: Optional[UUID]) -> Optional[UUID]:
    """OWNER tidak boleh punya toko. Dipakai saat membuat atau memindahkan user."""
    if store_id is not None and is_owner(user):
        raise ScopeError(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Akun OWNER bersifat lintas-toko dan tidak boleh punya store_id",
        )
    return store_id


def owned_store_query(db: Session, model, user: User, store_id: Optional[UUID] = None) -> Query:
    """Query dasar yang sudah ter-scope, dengan urutan bawaan terbaru dulu."""
    return store_filter(db.query(model), model, user, store_id).order_by(
        model.created_at.desc()
    )
