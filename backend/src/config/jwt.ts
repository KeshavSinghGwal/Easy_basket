export const JWT_SECRET: string = (() => {
  const s = process.env.JWT_SECRET;
  if (!s || s.length < 32) {
    console.error(
      '❌ JWT_SECRET is missing or shorter than 32 characters. Refusing to start.'
    );
    console.error(
      '💡 Generate one with: node -e "console.log(require(\'crypto\').randomBytes(48).toString(\'base64\'))"'
    );
    process.exit(1);
  }
  return s;
})();
