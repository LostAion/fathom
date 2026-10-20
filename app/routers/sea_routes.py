from typing import List
from fastapi import APIRouter, HTTPException, Query, status
from pydantic import BaseModel
import searoute

router = APIRouter(prefix="/sea-route", tags=["Sea Routes"])


class SeaRoute(BaseModel):
    distance_nm: float
    # [longitude, latitude] pairs along shipping lanes
    coordinates: List[List[float]]


@router.get("/", response_model=SeaRoute)
def get_sea_route(
    from_lat: float = Query(..., ge=-90, le=90),
    from_lon: float = Query(..., ge=-180, le=180),
    to_lat: float = Query(..., ge=-90, le=90),
    to_lon: float = Query(..., ge=-180, le=180),
):
    """Shortest route between two points along real shipping lanes (via Suez, Panama, etc.)."""
    try:
        route = searoute.searoute([from_lon, from_lat], [to_lon, to_lat], units="naut")
    except Exception as exc:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=f"No sea route found: {exc}")
    return SeaRoute(
        distance_nm=round(route["properties"]["length"], 1),
        coordinates=route["geometry"]["coordinates"],
    )
