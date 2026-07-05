import { useState, useEffect } from 'react';
import { FolderKanban, ChevronDown, ChevronRight, Monitor } from 'lucide-react';
import { formatLastSeen } from '../utils/interactionUtils';

function shortInstance(key) {
  if (!key) return 'Unknown session';
  if (key.length <= 14) return key;
  return key.slice(0, 8) + '…' + key.slice(-4);
}

export default function Sidebar({
  activeProject,
  activeInstance,
  onSelectProject,
  onSelectSession,
  projects = []
}) {
  const [expanded, setExpanded] = useState(() => new Set());

  useEffect(() => {
    if (!activeProject) return;
    setExpanded(prev => {
      const next = new Set(prev);
      next.add(activeProject);
      return next;
    });
  }, [activeProject]);

  const toggleExpanded = (projectKey, event) => {
    event.stopPropagation();
    setExpanded(prev => {
      const next = new Set(prev);
      if (next.has(projectKey)) next.delete(projectKey);
      else next.add(projectKey);
      return next;
    });
  };

  const totalCount = projects.reduce((sum, project) => sum + project.count, 0);
  const allSelected = activeProject === null && activeInstance === null;

  return (
    <aside className="thread-sidebar project-sidebar">
      <div className="sidebar-header">
        <FolderKanban size={16} color="var(--primary-accent)" />
        <span>Projects</span>
      </div>

      <ul className="thread-list project-tree">
        <li>
          <button
            className={`thread-item ${allSelected ? 'active' : ''}`}
            onClick={() => onSelectProject(null)}
          >
            <span className="thread-name">All projects</span>
            <span className="thread-count">{totalCount}</span>
          </button>
        </li>

        {projects.map(project => {
          const isExpanded = expanded.has(project.project_key);
          const projectActive = activeProject === project.project_key && activeInstance === null;
          const sessions = project.sessions || [];

          return (
            <li key={project.project_key} className="project-group">
              <div className={`project-row ${projectActive ? 'active' : ''}`}>
                <button
                  type="button"
                  className="project-expand"
                  aria-label={isExpanded ? 'Collapse project' : 'Expand project'}
                  onClick={(event) => toggleExpanded(project.project_key, event)}
                >
                  {sessions.length > 0
                    ? (isExpanded ? <ChevronDown size={14} /> : <ChevronRight size={14} />)
                    : <span className="project-expand-spacer" />}
                </button>
                <button
                  type="button"
                  className="project-select"
                  title={project.project_key === '__unassigned__' ? 'No workspace detected' : project.project_key}
                  onClick={() => onSelectProject(project.project_key)}
                >
                  <span className="thread-name">{project.label}</span>
                  <span className="project-meta">{formatLastSeen(project.last_timestamp)}</span>
                  <span className="thread-count">{project.count}</span>
                </button>
              </div>

              {isExpanded && sessions.length > 0 && (
                <ul className="session-list">
                  {sessions.map(session => {
                    const sessionActive =
                      activeProject === project.project_key &&
                      activeInstance === session.instance_key;

                    return (
                      <li key={session.instance_key}>
                        <button
                          type="button"
                          className={`session-item ${sessionActive ? 'active' : ''}`}
                          title={session.instance_key}
                          onClick={() => onSelectSession(project.project_key, session.instance_key)}
                        >
                          <Monitor size={12} />
                          <span className="session-name">{shortInstance(session.instance_key)}</span>
                          <span className="session-meta">{formatLastSeen(session.last_timestamp)}</span>
                          <span className="thread-count">{session.count}</span>
                        </button>
                      </li>
                    );
                  })}
                </ul>
              )}
            </li>
          );
        })}
      </ul>
    </aside>
  );
}
