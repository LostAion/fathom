from fastapi import FastAPI, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import RedirectResponse, JSONResponse
from sqlalchemy.exc import IntegrityError
from app.config import settings

# Import routers
from app.routers import (
    clients,
    brokers,
    surveyors,
    reinsurers,
    cargos,
    vessels,
    departments,
    underwriters,
    voyages,
    policies,
    claims,
    reinsured_by,
    assessed_by,
    carries,
    underwriting,
)

tags_metadata = [
    {"name": "Clients", "description": "Operations with insurance clients/policyholders."},
    {"name": "Brokers", "description": "Operations with insurance brokers and agencies."},
    {"name": "Surveyors", "description": "Operations with marine surveyors assessing risks and damage."},
    {"name": "Reinsurers", "description": "Operations with reinsurance entities."},
    {"name": "Cargos", "description": "Operations with insured cargo types and valuations."},
    {"name": "Vessels", "description": "Operations with insured marine vessels and ships."},
    {"name": "Departments", "description": "Operations with insurance firm internal departments."},
    {"name": "Underwriters", "description": "Operations with underwriting staff."},
    {"name": "Voyages", "description": "Operations with vessel voyage journeys."},
    {"name": "Policies", "description": "Operations with marine insurance policies (HULL, CARGO, PI)."},
    {"name": "Claims", "description": "Operations with claims filed against policies."},
    {"name": "Reinsured By (Junction)", "description": "Mappings of policies to reinsurers and share percentages."},
    {"name": "Assessed By (Junction)", "description": "Mappings of claims to assessing surveyors."},
    {"name": "Carries (Junction)", "description": "Mappings of voyages carrying cargo shipments."},
]

app = FastAPI(
    title="Marine Insurance Management API",
    description="""
# Marine Insurance REST API

A typed CRUD API built with **FastAPI** & **MariaDB** for managing marine insurance operations:
- **Clients, Brokers, Underwriters & Surveyors**
- **Vessels, Voyages & Cargos**
- **Policies & Claims**
- **Reinsurance & Junction Mappings**

Explore endpoints below, test request bodies, and view response schemas.
    """,
    version="1.0.0",
    openapi_tags=tags_metadata,
)

# Enable CORS for Frontend Development
app.add_middleware(
    CORSMiddleware,
    allow_origins=settings.parsed_cors_origins,
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Global Database IntegrityError Handler
@app.exception_handler(IntegrityError)
async def integrity_error_exception_handler(request: Request, exc: IntegrityError):
    orig = getattr(exc, "orig", None)
    error_detail = str(orig) if orig else str(exc)
    return JSONResponse(
        status_code=400,
        content={"detail": f"Database integrity error: {error_detail}"}
    )

# Root endpoint redirects to Swagger Docs
@app.get("/", include_in_schema=False)
def root():
    return RedirectResponse(url="/docs")

# Healthcheck Endpoint
@app.get("/api/health", tags=["Health"])
def health_check():
    return {
        "status": "healthy",
        "database": settings.DB_NAME,
        "docs_url": "/docs"
    }

# Include domain routers under /api
api_prefix = "/api"
app.include_router(clients.router, prefix=api_prefix)
app.include_router(brokers.router, prefix=api_prefix)
app.include_router(surveyors.router, prefix=api_prefix)
app.include_router(reinsurers.router, prefix=api_prefix)
app.include_router(cargos.router, prefix=api_prefix)
app.include_router(vessels.router, prefix=api_prefix)
app.include_router(departments.router, prefix=api_prefix)
app.include_router(underwriters.router, prefix=api_prefix)
app.include_router(voyages.router, prefix=api_prefix)
app.include_router(policies.router, prefix=api_prefix)
app.include_router(claims.router, prefix=api_prefix)
app.include_router(reinsured_by.router, prefix=api_prefix)
app.include_router(assessed_by.router, prefix=api_prefix)
app.include_router(carries.router, prefix=api_prefix)
app.include_router(underwriting.router, prefix=api_prefix)

