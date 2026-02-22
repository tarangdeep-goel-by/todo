"""Main FastAPI application."""
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from routers import agent, tasks, categories
from config import get_settings

settings = get_settings()

# Create FastAPI app
app = FastAPI(
    title="Todo Agent API",
    description="AI-powered voice-first todo list backend",
    version="1.0.0",
    debug=settings.debug
)

# Configure CORS for Flutter frontend
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],  # In production, replace with specific origins
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Include routers
app.include_router(agent.router, prefix="/api")
app.include_router(tasks.router, prefix="/api")
app.include_router(categories.router, prefix="/api")


@app.get("/health")
async def health():
    """Health check endpoint."""
    return {
        "status": "healthy",
        "environment": settings.app_env
    }


@app.get("/")
async def root():
    """Root endpoint."""
    return {
        "message": "Todo Agent API",
        "version": "1.0.0",
        "docs": "/docs"
    }
