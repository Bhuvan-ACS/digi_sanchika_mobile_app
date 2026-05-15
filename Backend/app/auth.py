from fastapi import APIRouter, HTTPException
from pydantic import BaseModel

router = APIRouter(prefix="/auth", tags=["Authentication"])

# TEMP USERS (Later connect DB)
fake_users_db = {
    "bhuvan@gmail.com": {
        "password": "Bhuvan@2001",
        "name": "Bhuvan",
        "employee_id": "2930"
    },
    "2930": {
        "password": "admin@1234",
        "name": "Bhuvan Varshit",
        "employee_id": "2930"
    }
}

class LoginRequest(BaseModel):
    email: str
    password: str

@router.post("/login")
async def login(request: LoginRequest):
    key = (request.email or "").strip().lower()
    user = fake_users_db.get(key) or fake_users_db.get(request.email)
    if not user or user["password"] != request.password:
        raise HTTPException(status_code=401, detail="Invalid Credentials")

    return {
        "message": "Login Successful",
        "name": user["name"],
        "email": request.email
}
