# Documento de Alcance — MVP
## Juego de Oleadas de Zombies — Roblox

**Versión:** 1.0
**Depende de:** `GDD-Zombie-Waves.md` (documento de diseño completo — este documento es un **subconjunto** de ese diseño, no lo sustituye ni contradice)
**Objetivo:** Bucle mínimo jugable para validar que el "core loop" de disparo + oleadas + economía + muerte se siente bien, antes de invertir en rebirth, mascotas, piezas de boss y monetización.

---

## 1. Qué SÍ entra en el MVP

### 1.1 Partida
- Servidor privado (Solo / Grupo con amigos). **Se pospone** el modo Público con matchmaking a una fase posterior.
- Máximo 4 jugadores (ya soportado por el sistema FPS existente, validar límite).

### 1.2 Oleadas y zombies
- Sistema de rondas incremental (ronda 1, 2, 3...) usando el sistema de disparo/`Humanoid` ya existente.
- **Solo 2-3 tipos de zombie** para el MVP (ej. normal + corredor), no todo el roster completo del GDD. El tanque, explosivo y a distancia se añaden después.
- Escalado simple de vida/velocidad/cantidad por ronda.
- **Sin boss todavía** — se pospone el sistema de boss cada 10 rondas a la fase 2, junto a piezas.

### 1.3 Vida y muerte
- Downed-state con reanimación gratis por compañeros (ventana de tiempo).
- **Sin sistema de revive con Robux todavía** — en el MVP, si nadie te reanima a tiempo, quedas fuera de la ronda hasta el wipe (sin opción de pagar). Esto se añade en la fase de monetización.
- Wipe de equipo = fin de partida, vuelta a ronda 1 en la siguiente partida.

### 1.4 Economía (solo la mitad de partida)
- **Oro de partida únicamente.** Se gana matando zombies, se gasta en partida, se pierde al wipe.
- **Sin moneda persistente todavía** — no hay hub, no hay progreso entre partidas en esta fase. (Esto es la simplificación más grande respecto al GDD completo, y es intencional para validar el core primero.)

### 1.5 Tienda en partida (simplificada)
- Una única máquina (o panel UI) donde comprar:
  - 2-3 armas básicas con oro.
  - 1-2 perks simples con efecto fijo (ej. más munición, recarga más rápida), también con oro.
- Sin niveles de perk, sin reducción de coste, sin slots — todo fijo, para simplificar. Estas capas se añaden en fase 2.

### 1.6 UI mínima
- HUD de vida, oro, ronda actual, munición.
- Pantalla de fin de partida (wipe) mostrando ronda alcanzada.

---

## 2. Qué NO entra en el MVP (pospuesto a fases siguientes, pero ya diseñado en el GDD)

| Sistema | Fase prevista |
|---|---|
| Moneda persistente + hub | Fase 2 |
| Rebirth (15 niveles, boost oro/XP/suerte) | Fase 2-3 |
| XP / nivel de cuenta y gating de contenido | Fase 2 |
| Bosses cada 10 rondas + piezas + fusión 10:1 | Fase 2 |
| Armas exclusivas crafteadas | Fase 3 |
| Mascotas (huevos, fusión, slots) | Fase 3 |
| Slots de perks comprables + reducción de coste | Fase 2 |
| Revive con Robux (Developer Product) | Fase de monetización |
| Game Passes (x2 Oro, x2 XP) | Fase de monetización |
| Developer Products (huevos premium, cajas de piezas) | Fase de monetización |
| Login diario (huevo o caja aleatoria) | Fase 3 |
| Modo público con matchmaking | Fase posterior, según tracción |
| Campo de tiro, VIP con oleada avanzada | Backlog |

---

## 3. Criterio de éxito del MVP

El MVP se considera validado cuando, jugando en grupo de 2-4 personas:

1. El disparo y la muerte de zombies se sienten satisfactorios (game feel del FPS ya existente aplicado a IA de zombies).
2. La escalada de dificultad ronda a ronda genera tensión progresiva sin picos injustos.
3. El downed-state + reanimación genera momentos de cooperación reales (no se ignora).
4. La decisión de "en qué gasto mi oro esta ronda" (arma vs. perk) se siente relevante, no trivial.
5. Al hacer wipe, hay ganas inmediatas de "una partida más" — aunque en el MVP eso no dé ninguna recompensa persistente todavía (esto último es información valiosa: si el "quiero repetir" no aparece ya en el MVP, el problema está en el core, no en la falta de meta-progresión).

Solo tras validar esto se recomienda pasar a Fase 2 (hub + moneda persistente + bosses/piezas), siguiendo el diseño completo en `GDD-Zombie-Waves.md`.