import type { Vector3 } from '@minecraft/server';

const getDistance = (a: Vector3, b: Vector3) => Math.hypot(a.x - b.x, a.y - b.y, a.z - b.z);

const getRandomFloat = (min: number, max: number) => Math.random() * (max - min + 1) + min;

const getRandomInteger = (min: number, max: number) => Math.floor(Math.random() * (max - min + 1)) + min;

export { getDistance, getRandomFloat, getRandomInteger };
