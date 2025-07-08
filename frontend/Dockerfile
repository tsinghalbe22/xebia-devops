# Base image
FROM node:18

# Set working directory
WORKDIR /app

# Copy and install
COPY package*.json ./
RUN npm install --legacy-peer-deps

# Copy source
COPY . .

# Expose frontend port
EXPOSE 3000

# Start frontend app
CMD ["npm", "start"]
