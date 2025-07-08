const fs = require('fs');
const path = require('path');

const filePath = path.join(__dirname, 'Product.js');

// Pool of working fake store image URLs
const fakeImages = [
  "https://fakestoreapi.com/img/81fPKd-2AYL._AC_SL1500_.jpg",
  "https://fakestoreapi.com/img/71li-ujtlUL._AC_UX679_.jpg",
  "https://fakestoreapi.com/img/71YXzeOuslL._AC_UY879_.jpg",
  "https://fakestoreapi.com/img/61IBBVJvSDL._AC_SY879_.jpg",
  "https://fakestoreapi.com/img/71HblAHs5xL._AC_UY879_.jpg",
  "https://fakestoreapi.com/img/51Y5NI-I5jL._AC_UX679_.jpg",
  "https://fakestoreapi.com/img/71z3kpMAYsL._AC_UY879_.jpg"
];

// Get N random images
const getRandomImages = (n = 5) => {
  const shuffled = [...fakeImages].sort(() => 0.5 - Math.random());
  return shuffled.slice(0, n);
};

fs.readFile(filePath, 'utf8', (err, data) => {
  if (err) throw err;

  // Replace all `images: [ ... ]`
  const updated = data.replace(/images:\s*\[[\s\S]*?\]/g, () => {
    const newImages = getRandomImages();
    const imageArray = newImages.map(url => `  "${url}"`).join(',\n');

    // Store the first image as thumbnail in a temporary map (if needed)
    lastUsedThumbnail = newImages[0];

    return `images: [\n${imageArray}\n]`;
  }).replace(/thumbnail:\s*"https:\/\/cdn\.dummyjson\.com\/product-images\/.*?\/thumbnail\.jpg"/g, () => {
    return `thumbnail: "${lastUsedThumbnail}"`;
  });

  fs.writeFile(filePath, updated, 'utf8', err => {
    if (err) throw err;
    console.log('✅ Images and thumbnails replaced successfully!');
  });
});
