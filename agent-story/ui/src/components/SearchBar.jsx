import { useState, useEffect } from 'react';
import { Search } from 'lucide-react';

const METHODS = ['ALL', 'GET', 'POST', 'PUT', 'DELETE', 'PATCH'];

export default function SearchBar({ onSearch, onMethodChange, method }) {
  const [term, setTerm] = useState('');

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
        id="method-filter"
        className="method-select"
        value={method}
        onChange={e => onMethodChange(e.target.value)}
      >
        {METHODS.map(m => (
          <option key={m} value={m}>{m}</option>
        ))}
      </select>
    </div>
  );
}
