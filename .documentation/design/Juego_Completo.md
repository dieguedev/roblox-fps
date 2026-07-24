# Documento de Diseño de Juego (GDD)
## Juego de Oleadas de Zombies — Roblox

**Versión:** 1.0
**Estado:** Diseño cerrado, pendiente de implementación
**Público objetivo del documento:** Agentes/desarrolladores encargados de la implementación en Roblox Studio / Luau

---

## 1. Visión general

Shooter cooperativo de oleadas de zombies en primera persona sobre la base FPS ya existente (disparo a `Humanoid` que reduce vida). El núcleo de rejugabilidad combina:

- Un bucle de **partida** (roguelite-like): cada partida empieza en la ronda 1 con equipo base, escala en dificultad, y termina en wipe de equipo, volviendo a ronda 1 en la siguiente partida.
- Un bucle de **meta-progresión persistente**: moneda persistente, XP de cuenta, rebirths, mascotas y armas exclusivas crafteadas, que **nunca** se resetean por morir y hacen cada partida sucesiva más fuerte/rápida.

Referencia de género: COD Zombies (perks, wall-buys, downed-state) + Roblox pet-sim/tycoon (rebirths, huevos gacha, moneda persistente) + shooters de oleadas actuales de Roblox (Survive Zombie Arena, Zombie Island).

---

## 2. Estructura de partidas

- **Modos de acceso** (elegidos desde el menú principal, no matchmaking automático único):
  - **Solo** — servidor privado de 1 jugador.
  - **Grupo privado** — creas una sala e invitas amigos.
  - **Público** — matchmaking abierto con desconocidos.
- **Tamaño máximo de partida:** 4 jugadores.
- El modo público es secundario; no requiere segmentación por "poder" (rebirth/progreso) en esta fase.

### 2.1 Lobby y sistema de party (arquitectura de servidores)
- Los jugadores caen en un **servidor público de lobby** (hub social), no directamente en la partida.
- Desde el lobby, un jugador crea una **party** eligiendo tamaño (1-4). Modo solo (tamaño 1) usa la misma UI de party con los botones de invitar deshabilitados.
- **Invitación limitada al mismo servidor público**: solo se puede invitar a jugadores presentes en tu mismo servidor de lobby (sin invitación cross-server en esta fase). La fusión con invitación nativa de Roblox a través de servidores queda para una fase posterior.
- La UI de party muestra los miembros actuales y su estado **ready/not ready**.
- El jugador que crea la party es el **host**: solo el host puede pulsar **Start**, y puede hacerlo con menos jugadores de los elegidos en cuanto todos los presentes estén ready (el tamaño elegido es un máximo, no un mínimo obligatorio).
- Si el host abandona la party antes de arrancar, el privilegio de host **pasa automáticamente** a otro miembro (la party no se disuelve).
- Al pulsar Start, el grupo completo se teletransporta (`TeleportService:ReserveServer` + `TeleportToPrivateServer`) a un **servidor reservado** dedicado exclusivamente a esa partida — esto es lo que hace que la partida sea un "servidor privado" real, aislado de cualquier otro grupo.
- Al terminar la partida (wipe o salida), **todo el grupo vuelve junto** a un servidor público de lobby.

### 2.2 Reglas de combate cooperativo
- **Sin fuego amigo**: el daño de las armas (a distancia y cuerpo a cuerpo) nunca afecta a otros jugadores, solo a zombies.

---

## 3. Vida, muerte y reset de partida

- Al llegar a 0 de vida, el jugador entra en **downed-state** (derribado, no muerto).
- **No puede morir por daño de zombie** estando downed — los zombies dejan de considerarlo objetivo válido y retargetean al jugador en pie más cercano (un downed no "tankea" para el equipo).
- Puede **arrastrarse** (movimiento lento) para acercarse a compañeros, pero no puede disparar ni atacar en este estado.
- Un compañero puede reanimarlo **gratis** manteniendo un canal pulsado junto a él durante unos segundos; si el canal se interrumpe (ej. el reanimador recibe un ataque), el progreso se reinicia.
- **Ventana de reanimación: 40 segundos** desde que entra en downed. Si expira sin reanimación, el jugador **muere** (queda fuera de la ronda actual) — el timer es intencionalmente generoso pero finito, precisamente para dejar sitio a la monetización de revive (sección 13.2): morir por timeout es la única forma de morir de verdad, y ahí es donde entra el revive de pago.
- Un jugador muerto puede ser revivido con **Robux** (Developer Product: paquete de 5 revives / 20 R$), volviendo a downed-state levantado inmediatamente.
- **Wipe de equipo** = todos los jugadores presentes están muertos y sin revives disponibles/comprados → la partida termina.
- Al terminar la partida (wipe):
  - Se pierde todo el progreso **de esa partida**: oro no gastado, ronda alcanzada, perks/armas activadas esa sesión. La siguiente partida arranca en ronda 1 con pistola base.
  - Se **banca automáticamente** (sin extracción física ni riesgo adicional) la moneda persistente y las piezas de boss ganadas durante la partida, calculadas en el momento del wipe.
  - Salir manualmente desde el menú también banca lo ganado hasta ese momento (no hay penalización extra por salir).

---

## 4. Economía dual

### 4.1 Oro (moneda de partida)
- Se gana matando zombies/bosses. Es **individual por jugador** (no un pozo compartido de equipo), igual que en CoD Zombies.
- **Cantidad por kill**: base fija (referencia MVP: 15) + bonus si el golpe final fue **headshot** (referencia: +10) o si el kill fue con **cuchillo** (referencia: +15, mayor que headshot por el riesgo de acercarse cuerpo a cuerpo). El bonus no depende del tipo de zombie, solo de cómo se hizo el kill.
- Se gasta en la partida en curso: máquinas de armas, máquinas de perks, Pack-a-Punch (sección 7.3).
- Se pierde por completo al wipe de equipo (no persiste entre partidas).

### 4.2 Moneda persistente
- Se gana **al final de cada partida** (wipe o salida manual), calculada de forma **individual** por jugador (no compartida por equipo), en base a:
  - Ronda máxima alcanzada por ese jugador (componente principal).
  - Bonus por objetivos: bosses derrotados, desempeño (headshots, supervivencia sin caer, etc.) — fórmula exacta a definir en balance.
- Se gasta en el **hub**: mejoras permanentes de stats, coste de rebirth, reducción de coste de perks en máquina, slots de perks/mascotas, compra de huevos, mejora de armas base (junto con XP, ver sección 8).
- **Importante:** no se comparte entre jugadores del mismo grupo. Cada jugador gana la suya según su propia ronda individual alcanzada, sea cual sea el resultado del equipo.

---

## 5. Sistema de Rebirth

- **Máximo de niveles:** 15.
- **Coste:** exponencialmente creciente por nivel (ej. `costo(n) = costoBase * factor^n`, factor y costoBase a definir en balance).
- **Al comprar un nivel de rebirth:**
  - Se **resetean a cero** las mejoras de stats permanentes compradas en el hub con moneda persistente (vida, daño base, etc. — cualquier stat mejorable por moneda persistente).
  - **NO se resetean:** cosméticos, armas exclusivas crafteadas, mascotas obtenidas. Las armas exclusivas **reescalan su daño** automáticamente a la fase/rebirth actual del jugador (para seguir siendo relevantes sin quedar rotas de poder en fases bajas).
  - Sube un multiplicador acumulado de **oro y XP ganados**, con un **tope global de +50%** (ej. cada nivel suma una fracción de ese 50% hasta agotar el margen en el nivel 15, o antes si se decide en balance).
  - Sube un valor de **"suerte"** acumulado, con un **tope de 50 puntos de suerte**, usado en la fórmula de probabilidad de rareza de:
    - Cajas de piezas de boss.
    - Huevos de mascotas.
    - (La fórmula matemática exacta de cómo "suerte" modifica las probabilidades base se define en la fase de balance técnico — debe evitar que en niveles altos las rarezas top se vuelvan casi garantizadas.)
- El **nivel de rebirth** en sí es un contador independiente sin relación con XP; solo depende de la moneda persistente acumulada.

---

## 6. Sistema de Perks (estilo CoD, Modelo D)

- Los perks (ej. "Carroñero" → más munición/reservas, "Quick Draw" → recarga/apuntado más rápido, etc.) se compran **siempre con oro de partida**, en máquinas dedicadas repartidas por el mapa.
- Si el jugador muere (pierde downed-state definitivamente) o empieza nueva partida, **pierde todos los perks activos**; debe volver a comprarlos.
- El **efecto de cada perk es fijo** (no escala con moneda persistente ni rebirth).
- Los perks son **acumulables entre sí** (no son mutuamente excluyentes): comprar un segundo perk no quita el efecto del primero, dentro del límite de slots disponibles. A diferencia de las armas, los perks **no rotan** su disponibilidad en la máquina — siempre están todos visibles y comprables.
- La moneda persistente, gastada en el hub, afecta **solo** a:
  - **Coste en oro** del perk en la máquina (reducción permanente de precio).
  - **Slots de perks disponibles** — el jugador empieza con un número base de slots (ej. 2) y desbloquea slots adicionales (ej. hasta 4) pagando moneda persistente en el hub.
- No hay niveles de "potencia" del perk en sí — solo economía de acceso.

---

## 7. Armas

### 7.1 Armas base/normales
- Disponibles en **máquinas expendedoras** repartidas por el mapa (conceptualmente wall-buy, implementado como interacción con máquina, no con una pared literal).
- Se compran con **oro de partida**.
- **Solo aparecen como comprables en la máquina** las armas que el jugador ya tiene **desbloqueadas** vía su **nivel de cuenta (XP)** — ver sección 8. Un arma no desbloqueada ni siquiera es seleccionable en la máquina.
- **Rotación aleatoria por ronda**: de todas las armas desbloqueadas por el jugador, la máquina oculta al azar aproximadamente un **10% del pool** cada ronda (`math.max(1, round(pool * 0.10))`, para garantizar que nunca se oculte todo si el pool es pequeño). Aunque el jugador tenga el arma desbloqueada y el oro para comprarla, esa ronda concreta puede no estar disponible — genera la tensión de "esta ronda toca conformarse". (En el MVP, sin sistema de desbloqueo por XP todavía, esta rotación aplica directamente sobre las 2-3 armas base fijas.)
- Comprar un arma **sustituye automáticamente** el arma del slot correspondiente (Primary/Secondary) según el tipo de arma comprada — no hay elección manual de slot, se infiere del tipo de arma.
- Se pierden al terminar la partida (hay que volver a comprarlas la siguiente run).

### 7.1.1 Cuchillo (arma cuerpo a cuerpo)
- Ataque por **raycast** desde la mira (mismo patrón que las armas de fuego: server-authoritative, sin depender del cliente), no un hitbox físico.
- **Rango corto** (referencia: 6 studs, similar al alcance de cuchillo de CS/Valorant — no hace falta estar literalmente pegado al enemigo, pero tampoco es un rango largo).
- **Daño 75**, con headshot **x2** (igual que el resto de armas) — el daño es **fijo**, no escala con la ronda (igual que el resto de armas, sección 11.2).
- **Cooldown ~0.6s** entre golpes.
- Kill con cuchillo da el bonus de oro más alto de todos los tipos de kill (sección 4.1), por el riesgo de acercarse cuerpo a cuerpo.
- **El one-shot de headshot es solo un efecto de las rondas tempranas, no una propiedad permanente del cuchillo**: al ser daño fijo (75x2=150) contra una vida de zombie que escala exponencialmente por ronda (sección 11.2), el headshot con cuchillo solo mata de un golpe a un normal mientras su vida siga en 150 (ronda 1). En cuanto la vida supera 150, ya no basta con un golpe — el margen se cierra rápido a partir de la ronda 2. Esto es intencional y refleja el propio comportamiento de CoD: el cuchillo es una herramienta de **farmeo de oro eficiente en rondas tempranas** (kill gratis, sin gastar munición, con el mejor bonus de oro), no un arma viable en rondas altas.

### 7.2 Armas exclusivas (crafteadas con piezas de boss)
- Se craftean **en el hub**, gastando piezas de boss (ver sección 9).
- Cada arma exclusiva tiene su propia **receta de crafteo** personalizada (mezcla de piezas de distintas rarezas según su poder) — no hay una fórmula única para todas.
- Una vez crafteada, el arma queda **desbloqueada permanentemente** (no se pierde con rebirth ni con la muerte). Su daño se **reescala automáticamente** según el rebirth/fase actual del jugador para mantenerse relevante.
- Pendiente de definir en fase técnica: si se equipan gratis al iniciar partida o requieren también compra en máquina especial dentro de la ronda (a decidir según balance, no cerrado explícitamente en el diseño — revisar con el usuario si genera dudas al implementar).

### 7.3 Pack-a-Punch (mejora de arma dentro de partida)
- Máquina física en el mapa, distinta de las máquinas de arma/perks, con coste en oro de partida.
- Mejora el arma que el jugador lleva equipada en ese momento: multiplica su daño base (referencia: ~x2 en el primer nivel, siguiendo el patrón real de CoD Zombies, donde Pack-a-Punch y rareza de arma se combinan de forma multiplicativa).
- El efecto está ligado a esa arma dentro de esa partida concreta: se pierde al wipe/nueva partida, igual que el resto de la economía de oro (no persiste como las armas exclusivas crafteadas de 7.2).
- Razón de diseño: la vida de los zombies escala exponencialmente por ronda (sección 11) mientras el daño base del arma se mantiene fijo — sin esta mejora, cualquier run tiene un techo de rondas alcanzable "gratis". El Pack-a-Punch es la única palanca in-game para extender ese techo, generando la decisión de gasto de oro central del juego.
- Pendiente de balance técnico: coste exacto, si hay más de un nivel de mejora (y su curva), y si aplica también al cuchillo.
- **Pospuesto respecto al MVP**: en el MVP el daño de arma es completamente fijo, sin ninguna mejora — el techo de dificultad lo genera únicamente el escalado de vida del zombie. El Pack-a-Punch se añade en Fase 2 junto al resto de sistemas de progresión.

---

## 8. XP y nivel de cuenta (gating de contenido)

- Sistema **paralelo e independiente** de la moneda persistente.
- El XP se gana jugando (con el multiplicador de rebirth aplicándose igual que al oro, tope +50%).
- Subir de **nivel de cuenta** desbloquea **qué contenido existe para comprar**: nuevas armas base, nuevos perks disponibles, nuevas zonas/huevos del hub, etc.
- Una vez desbloqueado por nivel, el jugador **compra/mejora de verdad** ese contenido gastando moneda persistente (mejoras) u oro (uso en partida).
- Es decir: **XP = qué puedes comprar. Moneda persistente = con qué lo compras/mejoras.**

---

## 9. Bosses y piezas

- Aparece un boss cada **10 rondas** (10, 20, 30...).
- Al derrotar al boss, el **equipo** recibe **siempre** una pieza (nunca hay drop vacío).
- La **rareza de la pieza** (Común, Rara, Muy Rara, Épica, Mítica, Legendaria) se determina por una tabla de probabilidades que depende de:
  - La ronda del boss derrotado (bosses de rondas más altas → mejores probabilidades de rareza alta).
  - El valor de "suerte" acumulado por rebirth (tope 50 puntos, ver sección 5).
- **La calidad de la pieza obtenida es compartida por evento de equipo** (todos los presentes en la pelea reciben pieza de la misma rareza determinada por ronda+suerte combinados del grupo) — a diferencia de la moneda persistente, que es individual. Esto incentiva jugar con jugadores de rebirth alto.
- **Fusión de piezas:** 10 piezas de una rareza = 1 pieza de la rareza inmediatamente superior (Común→Rara→Muy Rara→Épica→Mítica→Legendaria). Disponible en el hub.
- Las piezas se gastan crafteando armas exclusivas (sección 7.2), cada una con receta propia (ej. Arma X: 50 comunes + 20 raras + 10 muy raras + 5 épicas + 3 míticas + 2 legendarias; los números varían por arma según su poder).

---

## 10. Mascotas

- Se obtienen mediante **huevos gacha**, comprables con:
  - Moneda del juego (oro y/o moneda persistente — a definir en balance cuál exactamente).
  - **Robux** (huevos premium, con mejores probabilidades de rarezas altas, Developer Product de compra repetible).
- Rarezas equivalentes al sistema de piezas (Común → Legendaria).
- Cada mascota otorga un **bonus de oro por kill** proporcional a su rareza.
- **Fusión:** 10 mascotas de una rareza = 1 mascota de rareza superior (misma lógica que las piezas).
- **Equipamiento:** el jugador puede llevar **varias mascotas activas a la vez**, con sus bonus **sumándose**. Empieza con un número base de slots y puede desbloquear slots adicionales pagando en el hub (misma lógica que los slots de perks).
- Las mascotas **nunca se pierden** por rebirth ni por morir en partida.

---

## 11. Zombies y estructura de oleadas

- Múltiples tipos de zombie con **roles distintos** (no solo escalado de stats de un único tipo):
  - Zombie normal (base) — 150 HP en ronda 1.
  - Corredor rápido — 100 HP en ronda 1, más velocidad de movimiento y de ataque que el normal, a cambio de menos vida.
  - Tanque lento con mucha vida.
  - Explosivo (kamikaze).
  - A distancia (escupe/ataca a rango).
  - (Tanque, explosivo y a distancia ampliables en fase de balance/contenido — pospuestos respecto al MVP, que solo incluye normal + corredor.)
- Los tipos especiales se introducen **progresivamente** y se agrupan en **oleadas temáticas** (ej. ronda 7 = oleada de corredores, ronda 13 = oleada de tanques+explosivos combinados), no solo aparecen aleatoriamente mezclados desde el principio.
- Boss cada 10 rondas, con su propio kit de ataques/mecánica especial (a definir en diseño de contenido específico por boss).

### 11.1 IA de persecución y ataque
- **Navegación por `PathfindingService`** (no persecución en línea recta), con capacidad de saltar/trepar obstáculos — necesario porque el mapa tiene bastantes obstáculos y sin esto el jugador podría refugiarse en una superficie elevada fuera de alcance sin ningún riesgo.
- El objetivo de persecución es siempre el **jugador en pie más cercano** (sin lógica de aggro por daño recibido ni amenaza).
- Un jugador en **downed-state nunca es objetivo válido** (ver sección 3) — los zombies retargetean al jugador en pie más cercano.
- **Transición persecución → ataque**: al llegar a rango de melee, se lanza un único raycast de línea de visión; si hay algo de por medio (esquina, pilar), el zombie sigue persiguiendo un instante más en vez de atacar a través del obstáculo.
- **Ataque sincronizado por animación**: la animación de ataque lleva un `KeyframeMarker` en el fotograma exacto del golpe, y el daño se aplica en ese instante (no por un timer fijo en segundos) — así el daño nunca se desincroniza de la animación, sea cual sea su duración por tipo de zombie.

### 11.2 Escalado de dificultad por ronda
- **Vida por zombie**, fórmula real de CoD Zombies: rondas 1-9, `vida = vidaBase + 100 * (ronda - 1)`; ronda 10 en adelante, `vida = vida(ronda 9) * 1.1 ^ (ronda - 9)` (crecimiento exponencial sin techo). Cada tipo de zombie escala manteniendo su proporción relativa de vida respecto al normal.
- **Cantidad de zombies por ronda**: `cantidadBaseRonda(ronda) = min(round(6 + ronda * 1.5), 40)` — crece con la ronda y se estabiliza en un techo (~ronda 20-25), igual que en CoD la cantidad deja de subir a partir de cierto punto y la dificultad restante viene solo del escalado de vida.
- **Escala también con el número de jugadores presentes** (así funciona en CoD: la cantidad escala con jugadores, la vida individual no): `zombiesEnRonda = ceil(cantidadBaseRonda(ronda) * jugadoresPresentes / 4)`.
- **Sin límite artificial de zombies simultáneos en pantalla**: el techo de zombies activos a la vez es simplemente el total de la ronda (a diferencia del "máximo en pantalla" que sí existe en CoD real).
- **Spawn escalonado**: intervalo fijo entre apariciones, salvo que no quede ningún zombie activo y aún haya cola de la ronda — en ese caso se salta la espera y sale el siguiente inmediatamente (evita tiempos muertos si el equipo mata rápido).
- **Daño de arma fijo**, no escala automáticamente con la ronda (igual que en CoD) — la única forma de compensar el escalado de vida es el Pack-a-Punch (sección 7.3, pospuesto respecto al MVP).

---

## 12. Retención diaria

- **Recompensa de login diario:** cada día que el jugador entra, el juego determina **aleatoriamente y sin patrón fijo** si la recompensa es:
  - Un huevo de mascota gratis, o
  - Una caja de piezas gratis.
- No hay racha ni patrón predecible; puede tocar el mismo tipo varios días seguidos.
- (Misiones diarias/semanales quedan descartadas del diseño base; no se incluyen en esta fase.)

---

## 13. Monetización

### 13.1 Game Passes (compra única, permanente)
- **x2 Oro** — duplica permanentemente el oro ganado en partida.
- **x2 XP** — duplica permanentemente el XP ganado.
- *(Backlog / futuro, no en el diseño base cerrado):* **VIP** — permitiría empezar la partida desde una oleada más avanzada, u otros beneficios exclusivos a definir.

### 13.2 Developer Products (compra repetible)
- **Paquete de 5 revives** — 20 Robux (precio de referencia, ajustable).
- **Huevos premium de mascotas** — mejores probabilidades de rareza alta que los huevos gratuitos/de moneda de juego.
- **Cajas de piezas premium** — vía adicional de conseguir piezas de boss sin depender de derrotar bosses.

---

## 14. Elementos en backlog (no core, para fases futuras)

- **Campo de tiro** en el hub, para probar armas/daños sin gastar recursos.
- **Game Pass VIP** con inicio en oleada avanzada.
- Posible matchmaking segmentado por poder/rebirth en partidas públicas, si el modo público gana tracción.
- Pase de batalla estacional (descartado en esta fase por complejidad operativa).
- Misiones diarias/semanales (descartadas en favor del login diario simple).

---

## 15. Resumen del bucle de rejugabilidad (para referencia rápida)

```
PARTIDA (ronda 1 → wipe de equipo)
  ├─ Matar zombies → Oro → Comprar armas/perks en máquinas (temporal, se pierde al wipe)
  ├─ Cada 10 rondas → Boss → Pieza de rareza (compartida por equipo, según ronda+suerte)
  └─ Al wipe → Banco automático de:
        ├─ Moneda persistente (individual, según ronda propia alcanzada)
        ├─ Piezas de boss ganadas
        └─ XP de cuenta ganado

HUB (entre partidas)
  ├─ Moneda persistente → mejoras de stats, reducir coste de perks, slots, huevos, rebirth
  ├─ XP → desbloquea QUÉ armas/perks/contenido existen para comprar
  ├─ Piezas + fusión 10:1 → craftear armas exclusivas (permanentes, reescalan con rebirth)
  ├─ Huevos (moneda de juego o Robux) → mascotas (permanentes, bonus de oro acumulable)
  └─ Rebirth (máx. 15, coste exponencial) → resetea stats del hub,
        pero da +50% oro/XP tope y +50 suerte tope (mejor rareza en cajas/huevos)

→ Vuelta a PARTIDA, más fuerte que antes, con más razones para "una más"
```