// Districts served today (Dushanbe only) — shared between order creation
// and the registration step of login, so they can't drift apart.
const kDistricts = ['Сино', 'Фирдавси', 'Шохмансур', 'Исмоили Сомони'];

// The product currently covers a single city; kept as a list (not a bare
// constant) so the registration city picker is a real, extensible selector
// rather than hardcoded text.
const kCities = ['Душанбе'];
