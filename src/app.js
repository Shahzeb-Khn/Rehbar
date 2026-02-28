/**
 * Rehbar - App for people
 * Main application script
 */

const CATEGORIES = ['All', 'Health', 'Education', 'Legal', 'Finance', 'Community'];

const RESOURCES = [
  {
    id: 1,
    title: 'Community Health Centers',
    description: 'Find free and low-cost health services near you, including primary care and mental health support.',
    category: 'Health',
    link: '#',
  },
  {
    id: 2,
    title: 'Adult Education Programs',
    description: 'Access ESL classes, GED preparation, and vocational training programs in your area.',
    category: 'Education',
    link: '#',
  },
  {
    id: 3,
    title: 'Free Legal Aid',
    description: 'Connect with nonprofit legal clinics offering advice on immigration, housing, and family law.',
    category: 'Legal',
    link: '#',
  },
  {
    id: 4,
    title: 'Financial Literacy Resources',
    description: 'Learn budgeting, saving, and how to access affordable banking and microloan programs.',
    category: 'Finance',
    link: '#',
  },
  {
    id: 5,
    title: 'Food Assistance Programs',
    description: 'Locate food banks, meal programs, and SNAP enrollment help in your community.',
    category: 'Community',
    link: '#',
  },
  {
    id: 6,
    title: 'Mental Health Support',
    description: 'Culturally sensitive counseling and peer support groups available in multiple languages.',
    category: 'Health',
    link: '#',
  },
];

let activeCategory = 'All';
let searchQuery = '';

function escapeHtml(str) {
  return String(str)
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&#39;');
}

function renderCategories() {
  const container = document.getElementById('categories');
  container.innerHTML = CATEGORIES.map(
    (cat) =>
      `<button class="category-tag${cat === activeCategory ? ' active' : ''}" data-category="${cat}">${cat}</button>`
  ).join('');

  container.querySelectorAll('.category-tag').forEach((btn) => {
    btn.addEventListener('click', () => {
      activeCategory = btn.dataset.category;
      renderCategories();
      renderResources();
    });
  });
}

function renderResources() {
  const container = document.getElementById('resources');
  const query = searchQuery.toLowerCase().trim();

  const filtered = RESOURCES.filter((r) => {
    const matchesCategory = activeCategory === 'All' || r.category === activeCategory;
    const matchesSearch =
      !query ||
      r.title.toLowerCase().includes(query) ||
      r.description.toLowerCase().includes(query) ||
      r.category.toLowerCase().includes(query);
    return matchesCategory && matchesSearch;
  });

  if (filtered.length === 0) {
    container.innerHTML = '<p class="no-results">No resources found. Try a different search or category.</p>';
    return;
  }

  container.innerHTML = filtered
    .map(
      (r) => `
    <div class="resource-card">
      <span class="tag">${escapeHtml(r.category)}</span>
      <h3>${escapeHtml(r.title)}</h3>
      <p>${escapeHtml(r.description)}</p>
      <a class="card-link" href="${escapeHtml(r.link)}">Learn more &rarr;</a>
    </div>
  `
    )
    .join('');
}

function initSearch() {
  const input = document.getElementById('search-input');
  const btn = document.getElementById('search-btn');

  function doSearch() {
    searchQuery = input.value;
    renderResources();
  }

  btn.addEventListener('click', doSearch);
  input.addEventListener('keydown', (e) => {
    if (e.key === 'Enter') doSearch();
  });
}

function init() {
  renderCategories();
  renderResources();
  initSearch();
}

document.addEventListener('DOMContentLoaded', init);
