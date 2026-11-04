const API_BASE = '/api/v1/items';

document.addEventListener('DOMContentLoaded', () => {
    checkHealth();
    loadItems();
    document.getElementById('item-form').addEventListener('submit', handleCreateItem);
});

async function checkHealth() {
    const apiBadge = document.getElementById('api-status');
    const dbBadge = document.getElementById('db-status');

    try {
        const resHealth = await fetch('/health');
        if (resHealth.ok) {
            apiBadge.textContent = 'ONLINE (200)';
            apiBadge.className = 'badge ok';
        } else {
            apiBadge.textContent = 'ERRO';
            apiBadge.className = 'badge fail';
        }

        const resReady = await fetch('/health/ready');
        const dataReady = await resReady.json();
        if (resReady.ok && dataReady.database === 'connected') {
            dbBadge.textContent = 'CONECTADO';
            dbBadge.className = 'badge ok';
        } else {
            dbBadge.textContent = 'DESCONECTADO';
            dbBadge.className = 'badge fail';
        }
    } catch (err) {
        apiBadge.textContent = 'INDISPONÍVEL';
        apiBadge.className = 'badge fail';
        dbBadge.textContent = 'INDISPONÍVEL';
        dbBadge.className = 'badge fail';
    }
}

let allItems = [];

async function loadItems() {
    const tableBody = document.getElementById('items-table-body');
    try {
        const res = await fetch(API_BASE);
        if (res.ok) {
            const data = await res.json();
            allItems = data.items || [];
            renderItems(allItems);
        } else {
            tableBody.innerHTML = '<tr><td colspan="6" class="text-center">Erro ao carregar itens.</td></tr>';
        }
    } catch (err) {
        tableBody.innerHTML = '<tr><td colspan="6" class="text-center">Servidor offline ou sem conexão.</td></tr>';
    }
}

function renderItems(items) {
    const tableBody = document.getElementById('items-table-body');
    if (items.length === 0) {
        tableBody.innerHTML = '<tr><td colspan="6" class="text-center">Nenhum item cadastrado.</td></tr>';
        return;
    }

    tableBody.innerHTML = items.map(item => `
        <tr>
            <td>#${item.id}</td>
            <td><strong>${escapeHtml(item.title)}</strong></td>
            <td>${escapeHtml(item.description || '-')}</td>
            <td>R$ ${parseFloat(item.price).toFixed(2)}</td>
            <td><span class="badge ${item.is_active ? 'ok' : 'fail'}">${item.is_active ? 'Ativo' : 'Inativo'}</span></td>
            <td>
                <button onclick="deleteItem(${item.id})" class="btn btn-danger">Excluir</button>
            </td>
        </tr>
    `).join('');
}

async function handleCreateItem(e) {
    e.preventDefault();
    const payload = {
        title: document.getElementById('title').value,
        description: document.getElementById('description').value || null,
        price: parseFloat(document.getElementById('price').value),
        is_active: document.getElementById('is_active').checked
    };

    try {
        const res = await fetch(API_BASE, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify(payload)
        });

        if (res.status === 201) {
            document.getElementById('item-form').reset();
            loadItems();
        } else {
            alert('Erro ao salvar item. Verifique os dados inseridos.');
        }
    } catch (err) {
        alert('Falha na comunicação com a API.');
    }
}

async function deleteItem(id) {
    if (!confirm(`Deseja realmente excluir o item #${id}?`)) return;
    try {
        const res = await fetch(`${API_BASE}/${id}`, { method: 'DELETE' });
        if (res.status === 204) {
            loadItems();
        } else {
            alert('Não foi possível excluir o item.');
        }
    } catch (err) {
        alert('Erro ao excluir item.');
    }
}

function filterItems() {
    const query = document.getElementById('search-input').value.toLowerCase();
    const filtered = allItems.filter(item => item.title.toLowerCase().includes(query));
    renderItems(filtered);
}

function escapeHtml(str) {
    return str.replace(/[&<>'"]/g, 
        tag => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', "'": '&#39;', '"': '&quot;' }[tag] || tag)
    );
}