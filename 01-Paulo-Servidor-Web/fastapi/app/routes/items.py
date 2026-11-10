from fastapi import APIRouter, Depends, HTTPException, status, Query
from sqlalchemy.orm import Session
from typing import Optional
from app.database import get_db
from app.models.item import Item
from app.schemas.item import ItemCreate, ItemUpdate, ItemResponse, PaginatedItemResponse

router = APIRouter(prefix='/api/v1/items', tags=['Itens - CRUD'])

@router.post('', response_model=ItemResponse, status_code=status.HTTP_201_CREATED)
def create_item(item_in: ItemCreate, db: Session = Depends(get_db)):
    """Cadastra um novo item na base de dados."""
    db_item = Item(
        title=item_in.title,
        description=item_in.description,
        price=item_in.price,
        is_active=item_in.is_active
    )
    db.add(db_item)
    db.commit()
    db.refresh(db_item)
    return db_item

@router.get('', response_model=PaginatedItemResponse)
def list_items(
    skip: int = Query(0, ge=0, description='Quantidade de registros a pular'),
    limit: int = Query(10, ge=1, le=100, description='Limite de registros por página'),
    search: Optional[str] = Query(None, description='Busca por título'),
    db: Session = Depends(get_db)
):
    """Lista itens cadastrados com suporte a paginação e busca."""
    query = db.query(Item)
    if search:
        query = query.filter(Item.title.ilike(f'%{search}%'))
    
    total = query.count()
    items = query.order_by(Item.id).offset(skip).limit(limit).all()
    page = (skip // limit) + 1 if limit > 0 else 1
    return PaginatedItemResponse(total=total, page=page, size=limit, items=items)

@router.get('/{item_id}', response_model=ItemResponse)
def get_item(item_id: int, db: Session = Depends(get_db)):
    """Consulta um item específico pelo ID."""
    item = db.query(Item).filter(Item.id == item_id).first()
    if not item:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=f'Item com ID {item_id} não encontrado.'
        )
    return item

@router.put('/{item_id}', response_model=ItemResponse)
def update_item(item_id: int, item_in: ItemUpdate, db: Session = Depends(get_db)):
    """Atualiza um item existente."""
    item = db.query(Item).filter(Item.id == item_id).first()
    if not item:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=f'Item com ID {item_id} não encontrado.'
        )
    
    update_data = item_in.model_dump(exclude_unset=True)
    for field, value in update_data.items():
        setattr(item, field, value)
        
    db.commit()
    db.refresh(item)
    return item

@router.delete('/{item_id}', status_code=status.HTTP_204_NO_CONTENT)
def delete_item(item_id: int, db: Session = Depends(get_db)):
    """Remove um item da base de dados."""
    item = db.query(Item).filter(Item.id == item_id).first()
    if not item:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=f'Item com ID {item_id} não encontrado.'
        )
    db.delete(item)
    db.commit()
    return None
