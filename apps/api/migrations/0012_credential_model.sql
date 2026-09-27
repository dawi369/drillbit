-- The OpenRouter model a bring-your-own-key account chose. NULL keeps the app default.
ALTER TABLE credentials ADD COLUMN model TEXT;
