// Parse Gamery CSV export into game objects

export function parseGameryCSV(csvText) {
  const lines = [];
  let current = '';
  let inQuotes = false;

  // Handle multi-line quoted fields
  for (let i = 0; i < csvText.length; i++) {
    const char = csvText[i];
    if (char === '"') {
      inQuotes = !inQuotes;
      current += char;
    } else if ((char === '\n' || char === '\r') && !inQuotes) {
      if (current.trim()) lines.push(current);
      current = '';
      // Skip \r\n combo
      if (char === '\r' && csvText[i + 1] === '\n') i++;
    } else {
      current += char;
    }
  }
  if (current.trim()) lines.push(current);

  if (lines.length < 2) return [];

  const headers = parseCSVLine(lines[0]);
  const games = [];

  for (let i = 1; i < lines.length; i++) {
    const values = parseCSVLine(lines[i]);
    const row = {};
    headers.forEach((h, idx) => {
      row[h.trim()] = (values[idx] || '').trim();
    });

    // Map to our game structure
    if (row['Name']) {
      games.push({
        igdbId: row['IGDB ID'] || null,
        name: row['Name'],
        summary: (row['Summary'] || '').substring(0, 200),
        storyProgress: parseInt(row['Story Progress (1-100)']) || 0,
        overallProgress: parseInt(row['Overall Progress (1-100)']) || 0,
        userRating: parseFloat(row['User Rating (1-5)']) || null,
        status: mapStatus(row['Status']),
        platforms: (row['Library Platforms'] || '').split(',').map(p => p.trim()).filter(Boolean),
        releaseDate: row['First Release Date'] || null,
        addedDate: row['Added Date'] || null,
        completedDate: row['Completed Date'] || null,
      });
    }
  }

  return games;
}

function parseCSVLine(line) {
  const result = [];
  let current = '';
  let inQuotes = false;

  for (let i = 0; i < line.length; i++) {
    const char = line[i];
    if (char === '"') {
      if (inQuotes && line[i + 1] === '"') {
        current += '"';
        i++;
      } else {
        inQuotes = !inQuotes;
      }
    } else if (char === ',' && !inQuotes) {
      result.push(current);
      current = '';
    } else {
      current += char;
    }
  }
  result.push(current);
  return result;
}

function mapStatus(status) {
  if (!status) return 'backlog';
  const s = status.toLowerCase();
  if (s === 'playing') return 'playing';
  if (s === 'completed') return 'completed';
  if (s === 'abandoned') return 'abandoned';
  return 'backlog';
}
