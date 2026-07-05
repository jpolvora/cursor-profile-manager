import { useState, useEffect, useCallback } from 'react';
import { API } from './useAgentStoryEvents';

export function useProjects(refreshToken = 0) {
  const [projects, setProjects] = useState([]);

  const fetchProjects = useCallback(async () => {
    try {
      const res = await fetch(`${API}/api/projects`);
      if (res.ok) setProjects(await res.json());
    } catch (err) {
      console.error('Project list refresh failed:', err);
    }
  }, []);

  useEffect(() => {
    fetchProjects();
  }, [fetchProjects, refreshToken]);

  return projects;
}
