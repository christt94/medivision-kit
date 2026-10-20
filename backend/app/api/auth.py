from fastapi import APIRouter, Depends, HTTPException
from fastapi.security import OAuth2PasswordRequestForm
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.security import create_access_token, get_current_user, hash_password, verify_password
from app.db.database import get_db
from app.db.models import User
from app.schemas.auth import RegisterRequest, TokenResponse, UserResponse

router = APIRouter()


def _user_response(user: User) -> UserResponse:
    return UserResponse(
        id=user.id, username=user.username, full_name=user.full_name,
        role=user.role, is_active=user.is_active,
    )


@router.post("/register", response_model=UserResponse)
async def register(data: RegisterRequest, db: AsyncSession = Depends(get_db)):
    username = data.username.strip().lower()
    existing = await db.execute(select(User).where(User.username == username))
    if existing.scalar_one_or_none():
        raise HTTPException(409, detail="Nom utilisateur déjà utilisé")
    user = User(
        username=username, full_name=data.full_name.strip(),
        password_hash=hash_password(data.password), role="CLINICIAN",
    )
    db.add(user)
    await db.commit()
    await db.refresh(user)
    return _user_response(user)


@router.post("/login", response_model=TokenResponse)
async def login(form: OAuth2PasswordRequestForm = Depends(), db: AsyncSession = Depends(get_db)):
    result = await db.execute(select(User).where(User.username == form.username.strip().lower()))
    user = result.scalar_one_or_none()
    if not user or not user.is_active or not verify_password(form.password, user.password_hash):
        raise HTTPException(401, detail="Identifiants invalides")
    return TokenResponse(access_token=create_access_token(user), user=_user_response(user))


@router.get("/me", response_model=UserResponse)
async def me(user: User = Depends(get_current_user)):
    return _user_response(user)
