"""Registro explícito de los seis modelos del primer esquema."""
from app.modules.auth.models import User
from app.modules.gardens.models import Garden
from app.modules.plants.models import GrowthHistory, Plant, Species
from app.modules.watering.models import WateringEvent

__all__ = ["User", "Garden", "Species", "Plant", "GrowthHistory", "WateringEvent"]
from app.modules.auth.session_models import AuthSession, AuthRefreshToken, AuthRateLimit
__all__ += ["AuthSession", "AuthRefreshToken", "AuthRateLimit"]
from app.modules.common import models as mutation_models
