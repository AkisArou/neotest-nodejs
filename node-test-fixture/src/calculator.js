export function add(a, b) {
  return a + b;
}

export function divide(a, b) {
  if (b === 0) {
    throw new RangeError("Cannot divide by zero");
  }

  return a / b;
}

export async function doubleLater(value) {
  await new Promise((resolve) => setTimeout(resolve, 5));
  return value * 2;
}
