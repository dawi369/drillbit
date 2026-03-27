declare module "bun:test" {
  export function beforeEach(fn: () => void | Promise<void>): void;
  export function describe(name: string, fn: () => void): void;
  export const mock: {
    module(path: string, factory: () => Record<string, unknown>): void;
  };
  export function test(name: string, fn: () => void | Promise<void>): void;
  export function expect<T = unknown>(actual: T): {
    toBe(expected: unknown): void;
    toEqual(expected: unknown): void;
    toBeNull(): void;
  };
}
