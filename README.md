
       3D HORROR SYSTEMS PROTOTYPE (GODOT 4.X)
============================================================

A technical demonstration of core gameplay systems, focusing 
on scalable OOP architecture, state-based AI, and 
asynchronous interaction logic.

------------------------------------------------------------
1. OOP ARCHITECTURE: THE BASE ENTITY
------------------------------------------------------------
To ensure scalability, the project utilizes a "Base Entity" 
class that acts as a blueprint for all AI entities. 

The logic is governed by an enumerated Finite State Machine (FSM):
* IDLE: Default rest state; zero-velocity processing.
* WANDER: Search-based behavior using randomized coordinate 
  generation within navigation constraints.
* CHASE: High-priority state triggered by player detection 
  signals; updates velocity vectors toward the player node.
* ATTACKING: Proximity-based combat state (decoupled for 
  environment debugging).

------------------------------------------------------------
2. ASYNCHRONOUS INTERACTION SYSTEM (TERMINAL)
------------------------------------------------------------
The terminal interaction demonstrates a non-blocking task 
system that manages state over time:
* INPUT HANDLING: Listens for the 'E' key event via an 
  Area3D interaction volume.
* PROCESS LOGIC: Increments a float variable from 0% to 100%. 
* VISUAL FEEDBACK: Upon completion, a signal is emitted to 
  the OmniLight3D node to toggle visibility, proving 
  successful event communication between nodes.

------------------------------------------------------------
3. SPATIAL MOVEMENT: BLINK MECHANIC
------------------------------------------------------------
A short-range teleportation ability manipulating the Player's 
Global Transform:
* VECTOR MATH: Calculates the player’s forward_vector and 
  adds a fixed magnitude to the global_position.
* COOLDOWN CONTROLLER: Uses a Timer node as a logical gate 
  to prevent input spamming.

------------------------------------------------------------
4. EXTRACTION LOGIC
------------------------------------------------------------
The level loop is completed via a trigger zone at the door. 
Entering the zone triggers a scene transition, handling the 
handshake between the gameplay state and the win condition.

------------------------------------------------------------
TECHNICAL KEYWORDS: 
Object-Oriented Programming (OOP), Finite State Machine (FSM), 
Inheritance, Signals, Vector Math, Asynchronous Logic, 
Event-Driven Design.
============================================================
