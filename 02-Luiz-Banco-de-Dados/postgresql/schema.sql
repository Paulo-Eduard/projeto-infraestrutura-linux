-- Estrutura de referência compatível com fastapi/app/models/item.py.
-- O backend também pode criar esta tabela por Base.metadata.create_all().
-- Execute conectado ao banco infralab_db e como proprietário infralab_user.

CREATE TABLE IF NOT EXISTS public.items (
    id SERIAL PRIMARY KEY,
    title VARCHAR(100) NOT NULL,
    description VARCHAR(255),
    price DOUBLE PRECISION NOT NULL,
    is_active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS ix_items_id ON public.items (id);
CREATE INDEX IF NOT EXISTS ix_items_title ON public.items (title);
