import React, { useState } from 'react';
import { ChevronLeft } from 'lucide-react';
import MapViewer from './MapViewer.jsx';
import MapSection from './MapSection.jsx';

export default function MapPanel({
  game,
  deviceId,
  activeMapId,
  onActiveMapChange,
  onUpdateGame,
}) {
  const maps = game.maps || [];
  const activeMap = maps.find(m => m.id === activeMapId);
  const [isFullscreen, setIsFullscreen] = useState(false);

  return (
    <>
      <div className="flex flex-col h-full border border-white/10 rounded-xl overflow-hidden bg-black/20">
        {activeMap ? (
          <>
            <div className="flex items-center gap-2 px-3 py-2 border-b border-white/10 bg-black/30 shrink-0">
              <button
                onClick={() => onActiveMapChange(null)}
                className="flex items-center gap-1 text-xs text-gray-400 hover:text-white transition-colors"
              >
                <ChevronLeft className="w-3.5 h-3.5" />
                All maps
              </button>
            </div>
            <div className="flex-1 overflow-hidden">
              <MapViewer
                game={game}
                maps={maps}
                activeMapId={activeMapId}
                onMapSwitch={onActiveMapChange}
                onUpdateGame={onUpdateGame}
                mode="panel"
                onExpand={() => setIsFullscreen(true)}
              />
            </div>
          </>
        ) : (
          <div className="flex-1 overflow-y-auto">
            <MapSection
              game={game}
              deviceId={deviceId}
              onUpdateGame={onUpdateGame}
              activeMapId={activeMapId}
              onActiveMapChange={onActiveMapChange}
              panelMode
            />
          </div>
        )}
      </div>

      {isFullscreen && activeMap && (
        <MapViewer
          game={game}
          maps={maps}
          activeMapId={activeMapId}
          onMapSwitch={onActiveMapChange}
          onUpdateGame={onUpdateGame}
          mode="modal"
          onClose={() => setIsFullscreen(false)}
        />
      )}
    </>
  );
}
