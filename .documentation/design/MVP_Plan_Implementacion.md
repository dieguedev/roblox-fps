# Plan de Implementación — MVP
## Juego de Oleadas de Zombies — Roblox

**Depende de:** `MVP_Juego.md` (alcance) y `Juego_Completo.md` (diseño completo, referencia)
**Formato:** pasos verticales pequeños. Cada paso añade una porción jugable de principio a fin (server + client si aplica), no una capa horizontal completa (ej. "todos los sistemas de datos" o "toda la UI"). Cada paso termina en un punto en el que el juego se puede abrir en Studio sin estar roto y listo para un commit pequeño.
**Importante (reglas del proyecto):**
- Las pruebas en Roblox Studio las hace el usuario, nunca el agente. Cada paso incluye una sección "Cómo probarlo" con pasos claros y sencillos para que el usuario los ejecute.
- **Los commits los hace el usuario, no el agente.** Al terminar de implementar un paso, el agente solo sugiere un mensaje de commit (ver "Commit sugerido" en cada paso) y el "Cómo probarlo"; no ejecuta `git commit` ni ningún comando de git por su cuenta.

---

## Orden general y por qué

El core loop (perseguir → disparar → morir → escalar dificultad) se construye primero y se valida sin ningún envoltorio (sin lobby, sin tienda, sin downed-state) — igual que pide el propio documento de alcance ("validar el core antes de invertir en el resto"). El lobby/party se deja para el final porque es la pieza que decide *cómo llegas* a la partida, no cómo funciona la partida en sí; construirlo antes solo añadiría fricción a la hora de probar cada paso previo (habría que pasar por todo el flujo de invitación/ready cada vez que se quiere probar un cambio de IA de zombie).

---

## Paso 1 — Zombie que persigue y muere a balazos

**Qué se construye:**
- Un nuevo `Model` de zombie (reutilizando el patrón de `WeaponTestDummy`: `Humanoid` + `HealthBillboard`) con un script de IA nuevo que sustituye a `PatrolScript.server.lua`.
- Persecución mediante `PathfindingService`: recalcula ruta periódicamente hacia el jugador vivo más cercano, usando `Waypoints` y `Humanoid:MoveTo`. El objetivo de persecución es siempre el jugador en pie más cercano (sin lógica de aggro por daño recibido).
- El agente de pathfinding se configura con `AgentCanJump = true` (y, si el mapa lo requiere, `AgentCanClimb`) para que pueda saltar/trepar obstáculos — el mapa tiene bastantes obstáculos, y sin esto el jugador podría subirse a superficies elevadas y matar zombies sin ningún riesgo, rompiendo el core loop de riesgo/recompensa.
- Se aplica al modelo de zombie el mismo tratamiento que `disableAccessoryRaycasts` hace hoy para jugadores (`Handle.CanQuery = false` en accesorios/cosméticos), para que no bloqueen el raycast de headshot de las armas.
- **Sin fuego amigo**: el daño del raycast de arma solo debe aplicar a `Humanoid`s de zombie, nunca a otro jugador. Esto requiere revisar `WeaponService.server.lua` — hoy el raycast excluye solo al propio tirador (`FilterDescendantsInstances = {character}`), así que hay que añadir una comprobación explícita de que el modelo alcanzado es un zombie (no otro jugador) antes de aplicar daño.
- Sin ataque todavía. Sin rondas todavía. Un único zombie colocado a mano en el mapa de pruebas.
- Reutiliza tal cual el sistema de daño que ya existe en `WeaponService.server.lua` más allá del ajuste de fuego amigo de arriba.

**Cómo probarlo:**
1. Entra en Play Solo en Studio.
2. Camina lejos del zombie y confirma que empieza a perseguirte, incluso si hay un obstáculo entre medias (el mapa ya tiene obstáculos).
3. Dispárale hasta matarlo con el arma actual y confirma que muere igual que el dummy de pruebas.
4. Comprueba que si te escondes detrás de un obstáculo grande, el zombie lo rodea en vez de quedarse atascado empujando la pared.
5. Súbete a una superficie elevada/obstáculo del mapa y confirma que el zombie es capaz de saltar/subir para alcanzarte, en vez de quedarse abajo sin poder hacer nada.
6. Con 2 jugadores, confirma que dispararle a un compañero no le hace daño (sin fuego amigo).

**Commit sugerido:** "feature: Añade IA de zombie con persecución por pathfinding"

---

## Paso 2 — Ataque del zombie (animación + marcador + raycast de transición)

**Qué se construye:**
- Estado de "ataque": cuando el zombie está a rango de melee (~4-5 studs) del jugador, se lanza un único raycast de línea de visión; si está limpio, deja de perseguir y reproduce su animación de ataque.
- La animación de ataque lleva un `KeyframeMarker` (ej. `"Hit"`) colocado en el Animation Editor en el fotograma exacto del golpe; el daño se aplica vía `AnimationTrack:GetMarkerReachedSignal("Hit")`, comprobando que el jugador sigue en rango en ese instante.
- Cooldown entre ataques tras cada golpe conectado.
- Si el raycast de transición falla (hay algo de por medio), el zombie vuelve a modo persecución un instante más en vez de atacar a través de la pared.

**Cómo probarlo:**
1. Deja que el zombie te alcance en campo abierto y confirma que el daño llega justo cuando ves el "golpe" visual de la animación, no antes ni después.
2. Ponte justo detrás de un pilar/pared fina cuando el zombie esté cerca y confirma que NO te ataca a través de ella (debería rodear).
3. Encaja varios golpes seguidos y confirma que hay cooldown perceptible entre ataques (no te hace daño en cada frame).

**Commit sugerido:** "feature: Añade ataque de zombie sincronizado con marcador de animación"

---

## Paso 3 — Segundo tipo de zombie (corredor)

**Qué se construye:**
- Config de zombies (nuevo módulo, ej. `ZombieConfig.lua` en `ReplicatedStorage/Modules`, mismo espíritu que `WeaponConfig.lua`) con dos entradas: `Normal` (150 HP) y `Corredor` (100 HP, `WalkSpeed` mayor, cooldown de ataque menor).
- El script de IA del Paso 1-2 pasa a leer sus stats desde esta config en vez de tenerlos hardcodeados.
- Coloca manualmente un zombie de cada tipo en el mapa de pruebas para comparar.

**Cómo probarlo:**
1. Enfréntate a un Normal y a un Corredor por separado.
2. Confirma que el Corredor se mueve notablemente más rápido y muere con menos disparos.
3. Confirma que el Corredor te ataca con más frecuencia (cooldown más corto) que el Normal.

**Commit sugerido:** "feature: Añade zombie corredor y config de tipos de zombie"

---

## Paso 4 — Sistema de rondas

**Qué se construye:**
- `RoundService.server.lua`: contador de ronda, cola de zombies por ronda, y lógica de spawn:
  - Puntos de spawn fijos en el mapa (varios), elegidos al azar evitando el más cercano a cualquier jugador.
  - Spawn escalonado por intervalo fijo, salvo que no quede ningún zombie activo y aún haya cola (en ese caso, spawnea inmediatamente el siguiente sin esperar el intervalo).
  - Sin límite artificial de zombies simultáneos: el techo es el total de la ronda.
  - Ronda termina cuando cola vacía + cero zombies vivos.
  - Descanso fijo automático entre rondas (sin posibilidad de saltarlo ni de decidir cuándo empieza la siguiente).
- **Cantidad de zombies por ronda**, dos factores combinados:
  - Cantidad base por ronda (crece con la ronda, con techo — igual que en CoD la cantidad deja de subir a partir de cierta ronda y la dificultad restante viene solo del escalado de vida): `cantidadBaseRonda(ronda) = min(round(6 + ronda * 1.5), 40)`. Ej.: ronda 1 ≈ 8, ronda 10 ≈ 21, ronda 20 ≈ 36, ronda 25+ = 40 (techo).
  - Escala según el número de jugadores presentes (así funciona también en CoD Zombies: escala la cantidad, no la vida individual): `zombiesEnRonda = ceil(cantidadBaseRonda(ronda) * jugadoresPresentes / 4)`, con mínimo 1. Una partida en solitario tiene menos zombies por ronda que una de 4, pero cada zombie individual tiene la misma vida en ambos casos (la vida depende solo de la ronda, no del tamaño de grupo).
- Escalado de vida por ronda, fórmula real de CoD Zombies:
  - Rondas 1-9: `vida = vidaBase + 100 * (ronda - 1)`.
  - Ronda 10+: `vida = vida(ronda 9) * 1.1 ^ (ronda - 9)`.
  - Aplicado a `Normal` (vidaBase 150) tal cual; `Corredor` mantiene la misma proporción relativa (≈66.7% de la vida del Normal) en cada ronda.
  - (Velocidad de zombie por ronda: no escala, ya es fija por tipo desde el Paso 3 — solo la vida y la cantidad escalan por ronda.)
- HUD: añade número de ronda actual (reutilizando el patrón ya existente de atributos + UI del `AmmoUI`).

**Cómo probarlo:**
1. Juega varias rondas seguidas en solitario.
2. Confirma que los zombies de rondas altas (ej. ronda 8-10) aguantan claramente más disparos que en la ronda 1.
3. Confirma que tras matar al último zombie de una ronda hay un descanso fijo antes de que empiece la siguiente, y que no hay ningún botón para saltarlo.
4. Confirma que el HUD muestra el número de ronda correcto en todo momento.
5. Compara la misma ronda jugada en solitario vs. con 2+ jugadores y confirma que salen menos zombies estando solo (misma vida por zombie, menos cantidad).

**Commit sugerido:** "feature: Añade sistema de rondas con escalado de vida y spawn combinado"

---

## Paso 5 — Economía de oro

**Qué se construye:**
- Oro por jugador (server-owned, como el resto del estado en `WeaponService`), no compartido.
- Al matar un zombie: oro base fijo + bonus si el golpe final fue headshot o con cuchillo (cuchillo llega en el Paso 6; de momento solo el bonus de headshot es alcanzable).
- Oro se resetea a 0 al empezar cada partida/wipe.
- HUD: número de oro actual, mismo patrón que ronda/munición.

**Cómo probarlo:**
1. Mata zombies con headshot y sin headshot, confirma que el oro sube más con headshot.
2. Confirma que cada jugador (si pruebas con 2 clientes) tiene su propio contador independiente.

**Commit sugerido:** "feature: Añade economía de oro por partida con bonus de headshot"

---

## Paso 6 — Cuchillo funcional

**Qué se construye:**
- Ataque de cuchillo: raycast desde la mira (mismo patrón que las armas de fuego), rango ~6 studs, daño 75, headshot x2, cooldown ~0.6s.
- Se añade `Damage`, `BulletRange` (o campo equivalente para el rango de melee) y `HeadshotMultiplier` a la entrada `Knife` de `WeaponConfig.lua`, y el flujo de disparo de `WeaponService.server.lua` se extiende para manejar el caso `Type == "Melee"` en vez de ignorarlo como hoy.
- Conecta con el bonus de oro por kill-de-cuchillo del Paso 5.

**Cómo probarlo:**
1. Equipa el cuchillo y remata zombies de cerca.
2. Confirma que un headshot con cuchillo mata a un Normal (150 HP) de un solo golpe, y que un golpe al cuerpo no.
3. Confirma que el kill con cuchillo da el bonus de oro correspondiente.
4. Confirma que hay un cooldown perceptible entre golpes (no puedes spamear).

**Commit sugerido:** "feature: Implementa ataque de cuchillo con raycast y bonus de oro"

---

## Paso 7 — Tienda física (armas + perks)

**Qué se construye:**
- Máquina interactuable en el mapa (`ProximityPrompt` o similar) con UI de compra.
- Compra de arma: sustituye automáticamente el arma del slot correspondiente (Primary/Secondary) según el tipo de arma comprada, gastando oro.
- Rotación aleatoria de armas mostradas: `math.max(1, round(pool * 0.10))` armas ocultas cada ronda, recalculado cada ronda.
- Compra de perks: 1-2 perks de efecto fijo, siempre disponibles (sin rotación), acumulables entre sí (comprar uno no quita el otro).
- Los efectos de los perks (ej. más munición reserva, recarga más rápida) se aplican leyendo un estado server-side por jugador, similar a `ammoState`.

**Cómo probarlo:**
1. Acércate a la máquina, confirma que se abre la UI de compra.
2. Compra un arma nueva y confirma que sustituye la de su slot correspondiente.
3. Recarga varias veces la partida (o espera varias rondas) y confirma que las armas disponibles en la máquina cambian entre rondas.
4. Compra los dos perks y confirma que ambos efectos están activos a la vez (no se pisan).
5. Intenta comprar sin oro suficiente y confirma que la compra se rechaza.

**Commit sugerido:** "feature: Añade tienda física con rotación de armas y perks acumulables"

---

## Paso 8 — Downed-state y reanimación

**Qué se construye:**
- Al llegar a 0 de vida: en vez de morir, el jugador entra en downed-state (Humanoid no muere, se bloquea disparo/salto/sprint, se activa animación/pose de caído).
- Movimiento reducido tipo arrastre, solo para acercarse a compañeros (no hay "huir del peligro" real porque no puede morir por zombie).
- Los zombies dejan de considerar como objetivo válido a un jugador downed (retargeting al jugador en pie más cercano).
- Reanimación: canal de compañero mantenido pulsado durante X segundos junto al downed, que se reinicia si se interrumpe.
- Timer de 40s desde que entra en downed: si nadie lo reanima a tiempo, pasa a "fuera de la ronda" (spectator hasta el wipe).
- **Importante — conflicto con `HealthRegenService.server.lua`:** ese script hoy regenera 2 HP/s a cualquier `Humanoid` con `Health < MaxHealth` que lleve 5s sin recibir daño. Sin exclusión explícita, un jugador downed y solo (sin compañeros cerca atacándolo, ya que los zombies lo ignoran) se auto-curaría desde 0 a los 5s, revive automático sin compañero, rompiendo la mecánica entera. Hay que excluir explícitamente a los jugadores en downed-state de este regen.

**Cómo probarlo (necesita 2 jugadores/clientes):**
1. Deja que un zombie te baje a 0 de vida y confirma que entras en downed en vez de morir.
2. Confirma que los zombies dejan de atacarte estando downed.
3. Arrástrate hacia tu compañero y confirma que puedes acercarte.
4. Que tu compañero te reanime manteniendo el botón cerca de ti, y confirma que si un zombie le interrumpe a medio canal, el progreso se reinicia.
5. Deja pasar los 40s sin reanimar y confirma que quedas fuera de la ronda (modo espectador) hasta el wipe.
6. Quédate downed y solo (sin compañeros cerca) durante más de 5s, y confirma que tu vida NO empieza a subir sola (el regen no debe aplicarse en downed-state).

**Commit sugerido:** "feature: Añade downed-state con reanimación y timer de sangrado"

---

## Paso 9 — Wipe y pantalla de fin de partida

**Qué se construye:**
- Detección de wipe: todos los jugadores presentes están "fuera de la ronda" (downed expirado) simultáneamente.
- Pantalla de fin de partida: ronda alcanzada por el equipo.
- Reset de estado de partida (oro a 0, ronda a 1, armas al loadout base) preparado para una posible partida siguiente en el mismo servidor reservado.

**Cómo probarlo:**
1. Provoca un wipe (deja que expiren los timers de downed de todos los jugadores presentes).
2. Confirma que aparece la pantalla de fin de partida con la ronda correcta.
3. Confirma que, si se reinicia la partida, todo vuelve a ronda 1 con oro a 0 y loadout base.

**Commit sugerido:** "feature: Añade detección de wipe y pantalla de fin de partida"

---

## Paso 10 — Lobby y sistema de party

**Qué se construye (el más grande, puede dividirse en sub-commits si conviene sobre la marcha):**
- Zona de lobby física en un servidor público (donde caen los jugadores al entrar al juego).
- UI de creación de party: elegir tamaño 1-4.
- Invitación limitada a jugadores presentes en el mismo servidor público (lista de jugadores del lobby, sin invitación cross-server).
- UI de party: miembros actuales, estado ready/not ready por miembro, botón "Start" visible solo para el host.
- Si el host abandona la party antes de arrancar, el privilegio de host pasa automáticamente a otro miembro.
- Modo solo (tamaño 1): misma UI de party, con los botones de invitar deshabilitados, listo para pulsar Start directamente.
- Al pulsar Start: `TeleportService:ReserveServer()` + `TeleportToPrivateServer()` de todo el grupo a un servidor reservado dedicado a esa partida (contiene el mapa de arena con los sistemas de los Pasos 1-9).
- Al terminar la partida (wipe o salida): teletransporte conjunto de los 4 de vuelta a un servidor público de lobby.

**Cómo probarlo (necesita varios clientes/cuentas, o Studio + clientes reales según lo que permita probar el teletransporte):**
1. Entra al lobby y confirma que ves la UI de creación de party con las opciones 1-4.
2. Con un segundo jugador en el mismo servidor, invítalo y confirma que le llega la invitación y puede unirse.
3. Confirma que el estado ready/not ready se refleja correctamente para cada miembro.
4. Confirma que solo el host ve/puede pulsar Start, y que Start funciona incluso si no se llenó el tamaño elegido (basta con que los presentes estén ready).
5. Sal de la party siendo host y confirma que el privilegio pasa a otro miembro sin disolver la party.
6. Pulsa Start y confirma que el grupo aterriza junto en el servidor de arena.
7. Provoca un wipe y confirma que los 4 vuelven juntos a un servidor de lobby público al final.
8. Con los 4 jugadores reales a la vez en el servidor de arena, confirma que no hay lag/errores al disparar, recargar o comprar todos a la vez — el documento de alcance pide validar explícitamente que el sistema FPS existente aguanta bien el máximo de 4 (nunca se ha probado con 4 reales simultáneos).

**Commit sugerido:** "feature: Añade lobby, sistema de party y teletransporte a servidor reservado"

---

## Notas de riesgo técnico a vigilar durante la implementación

- **Rendimiento de `PathfindingService`** con muchos zombies activos a la vez en rondas altas (el techo de zombies simultáneos es el total de la ronda, sin límite artificial, según se decidió) — vigilar en playtesting si rondas altas generan lag apreciable; si ocurre, es un ajuste de implementación (ej. recalcular ruta con menor frecuencia, no un cambio de diseño).
- **Escalado de vida a rondas muy altas** (ronda 100 ≈ 5.5M HP según la fórmula de CoD) puede acabar generando números de daño/vida que choquen con límites de precisión de `Humanoid.Health` — improbable que se llegue tan lejos en el MVP, pero si el playtesting revela partidas muy largas, revisar.
