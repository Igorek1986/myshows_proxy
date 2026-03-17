import os

import httpx
from fastapi import FastAPI, HTTPException
from pydantic import BaseModel

MYSHOWS_AUTH_URL = os.getenv("MYSHOWS_AUTH_URL", "https://myshows.me/api/session")

app = FastAPI(title="MyShows Auth Proxy")


class AuthRequest(BaseModel):
    login: str
    password: str


@app.post("/myshows/auth")
async def proxy_auth(body: AuthRequest):
    try:
        async with httpx.AsyncClient() as client:
            response = await client.post(
                MYSHOWS_AUTH_URL,
                json={"login": body.login, "password": body.password},
                headers={"Content-Type": "application/json"},
                timeout=10.0,
            )

        if response.status_code != 200:
            raise HTTPException(
                status_code=response.status_code,
                detail="MyShows authentication failed",
            )

        auth_data = response.json()
        token = auth_data.get("token")
        refresh_token = auth_data.get("refreshToken")
        token_v3 = response.cookies.get("msAuthToken")

        if not token:
            raise HTTPException(status_code=500, detail="No token received from MyShows")

        return {"token": token, "token_v3": token_v3, "refreshToken": refresh_token}

    except httpx.RequestError:
        raise HTTPException(status_code=503, detail="Service temporarily unavailable")
