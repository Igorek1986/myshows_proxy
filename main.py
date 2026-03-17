import logging
import os

import httpx
from fastapi import FastAPI, HTTPException, Request
from pydantic import BaseModel

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

MYSHOWS_AUTH_URL = os.getenv("MYSHOWS_AUTH_URL", "https://myshows.me/api/session")

app = FastAPI(title="MyShows Auth Proxy")


class AuthRequest(BaseModel):
    login: str
    password: str


@app.post("/myshows/auth")
async def proxy_auth(body: AuthRequest):
    try:
        logger.info(f"Auth request for login: {body.login}")

        async with httpx.AsyncClient() as client:
            response = await client.post(
                MYSHOWS_AUTH_URL,
                json={"login": body.login, "password": body.password},
                headers={"Content-Type": "application/json"},
                timeout=10.0,
            )

        if response.status_code != 200:
            logger.error(f"MyShows auth failed: {response.status_code} - {response.text}")
            raise HTTPException(
                status_code=response.status_code,
                detail="MyShows authentication failed",
            )

        auth_data = response.json()
        token = auth_data.get("token")
        refresh_token = auth_data.get("refreshToken")
        token_v3 = response.cookies.get("msAuthToken")

        logger.info(f"auth_data: {auth_data}")
        logger.info(f"Cookies: {response.cookies}")

        if not token:
            logger.error("No token received from MyShows")
            raise HTTPException(status_code=500, detail="No token received from MyShows")

        logger.info(f"Successfully authenticated: {body.login}")
        return {"token": token, "token_v3": token_v3, "refreshToken": refresh_token}

    except httpx.RequestError as e:
        logger.error(f"Request to MyShows failed: {str(e)}")
        raise HTTPException(status_code=503, detail="Service temporarily unavailable")
