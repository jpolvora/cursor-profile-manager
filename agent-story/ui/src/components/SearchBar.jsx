import { useState, useEffect } from 'react';
import { Search, X } from 'lucide-react';

const METHODS = ['ALL', 'GET', 'POST', 'PUT', 'DELETE', 'PATCH'];

export default function SearchBar({
  onSearch,
  onMethodChange,
  method,
  projects,
  projectFilter,
  onProjectChange,
  onClearFilters,
  filtersActive,
  externalSearchTerm = ''
}) {
  const [term, setTerm] = useState('');

  useEffect(() => {
    setTerm(externalSearchTerm);
  }, [externalSearchTerm]);

  useEffect(() => {
    const timer = setTimeout(() => {
      onSearch(term);
    }, 300);
    return () => clearTimeout(timer);
  }, [term, onSearch]);

  return (
    <div className="search-bar">
      <div className="search-input-wrapper">
        <Search size={16} className="search-icon" />
        <input
          id="search-input"
          type="text"
          className="search-input"
          placeholder="Search requests and responses..."
          value={term}
          onChange={e => setTerm(e.target.value)}
        />
      </div>

      <select
        id="project-filter"
        className="filter-select project-select-filter"
        value={projectFilter ?? ''}
        onChange={e => onProjectChange(e.target.value || null)}
        title="Filter by detected project"
      >
        <option value="">All projects</option>
        {projects.map(project => (
          <option key={project.project_key} value={project.project_key}>
            {project.label} ({project.count})
          </option>
        ))}
      </select>

      <select
        id="method-filter"
        className="filter-select method-select"
        value={method}
        onChange={e => onMethodChange(e.target.value)}
      >
        {METHODS.map(m => (
          <option key={m} value={m}>{m}</option>
        ))}
      </select>

      {filtersActive && (
        <button
          type="button"
          className="clear-filters-btn"
          onClick={onClearFilters}
          title="Clear all filters"
        >
          <X size={14} />
          Clear filters
        </button>
      )}
    </div>
  );
}
