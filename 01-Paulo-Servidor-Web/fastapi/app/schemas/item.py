from pydantic import BaseModel, Field, ConfigDict
from typing import Optional, List
from datetime import datetime

class ItemBase(BaseModel):
    title: str = Field(..., min_length=1, max_length=100, description="Título do item")
    description: Optional[str] = Field(None, max_length=255, description="Descrição do item")
    price: float = Field(..., gt=0, description="Preço do item (maior que zero)")
    is_active: bool = Field(True, description="Status de ativação do item")

class ItemCreate(ItemBase):
    pass

class ItemUpdate(BaseModel):
    title: Optional[str] = Field(None, min_length=1, max_length=100)
    description: Optional[str] = Field(None, max_length=255)
    price: Optional[float] = Field(None, gt=0)
    is_active: Optional[bool] = None

class ItemResponse(ItemBase):
    id: int
    created_at: datetime
    updated_at: Optional[datetime] = None

    model_config = ConfigDict(from_attributes=True)

class PaginatedItemResponse(BaseModel):
    total: int
    page: int
    size: int
    items: List[ItemResponse]
