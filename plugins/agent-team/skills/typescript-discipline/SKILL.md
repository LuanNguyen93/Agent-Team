---
name: typescript-discipline
description: Strict TypeScript discipline and idiomatic type patterns distilled from Matt Pocock's advanced guidelines. Use when designing types, writing robust interfaces, eliminating `any`, or creating reusable generic utilities.
when_to_use: Designing API types, refactoring complex types, building reusable utility types, or eliminating unsafe type assertions.
paths:
  - "**/*.ts"
  - "**/*.tsx"
---

# TypeScript Discipline

Write type-safe, inference-first TypeScript that guides developer intent and catches bugs at compile-time without adding unnecessary runtime baggage.

## Core Rules

1. **Derive Types from Values & Inferences (Inference First)**
   - Let TypeScript infer whenever possible.
   - Use `as const` for literal arrays and objects to preserve exact types.
   - Use `typeof` and indexed access (`T[keyof T]`) rather than manually duplicating types.

2. **Ban Unsafe Escapes**
   - **Never use `any`**. Use `unknown` when the type is truly uncertain, and narrow with Type Guards or Zod/Valibot schemas before usage.
   - Avoid `as unknown as T` double assertions. If you must cast, write an explicit assertion function or type predicate (`val is TargetType`).
   - Ban non-null assertion operator (`!`) unless immediately guarded or within isolated test assertions.

3. **Exhaustive Pattern Matching**
   - When switching or matching on discriminated unions, always implement an exhaustive check using `assertNever`:
   ```ts
   export function assertNever(x: never): never {
     throw new Error(`Unexpected object: ${JSON.stringify(x)}`);
   }
   ```

4. **Branded Types for Primitive Domain IDs**
   - Prevent passing a `UserId` into a function expecting a `PostId`:
   ```ts
   declare const brand: unique symbol;
   export type Brand<T, K extends string> = T & { readonly [brand]: K };

   export type UserId = Brand<string, 'UserId'>;
   export type PostId = Brand<string, 'PostId'>;
   ```

5. **Generics & Function Signatures**
   - Constrain generic type parameters (`<T extends Record<string, unknown>>`).
   - Explicit return types are required on public library APIs, exported route handlers, and exported helper functions. Internal helper functions can rely on inference.

6. **Self-Review Checklist**
   - [ ] No `any` keyword in the file.
   - [ ] Discriminated unions have a common literal discriminator field (e.g., `kind` or `status`).
   - [ ] Reusable types avoid deeply nested recursive types that slow down the type-checker.
