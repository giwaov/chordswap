/** @type {import('tailwindcss').Config} */
export default {
  content: [
    "./index.html",
    "./src/**/*.{js,ts,jsx,tsx}",
  ],
  theme: {
    extend: {
      colors: {
        arc: {
          primary: '#6366f1',
          secondary: '#8b5cf6',
          dark: '#0f0f23',
          darker: '#09091a',
          accent: '#22d3ee',
        }
      }
    },
  },
  plugins: [],
}
