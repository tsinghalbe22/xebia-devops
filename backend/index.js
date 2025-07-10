require("dotenv").config()
const express = require('express')
const cors = require('cors')
const morgan = require("morgan")
const cookieParser = require("cookie-parser")
const authRoutes = require("./routes/Auth")
const productRoutes = require("./routes/Product")
const orderRoutes = require("./routes/Order")
const cartRoutes = require("./routes/Cart")
const brandRoutes = require("./routes/Brand")
const categoryRoutes = require("./routes/Category")
const userRoutes = require("./routes/User")
const addressRoutes = require('./routes/Address')
const reviewRoutes = require("./routes/Review")
const wishlistRoutes = require("./routes/Wishlist")
const { connectToDB } = require("./database/db")
const { metricsRouter, trackRequests } = require('./middleware/Metrics');

// server init
const server = express()

// database connection
connectToDB()

// middlewares
server.use(cors({
    origin: process.env.ORIGIN,
    credentials: true,
    exposedHeaders: ['X-Total-Count'],
    methods: ['GET', 'POST', 'PATCH', 'DELETE']
}))
server.use(express.json())
server.use(cookieParser())
server.use(morgan("tiny"))

// IMPORTANT: Add trackRequests BEFORE your routes
server.use(trackRequests);

// routeMiddleware
server.use("/auth", authRoutes)
server.use("/users", userRoutes)
server.use("/products", productRoutes)
server.use("/orders", orderRoutes)
server.use("/cart", cartRoutes)
server.use("/brands", brandRoutes)
server.use("/categories", categoryRoutes)
server.use("/address", addressRoutes)
server.use("/reviews", reviewRoutes)
server.use("/wishlist", wishlistRoutes)

// Add metrics router
server.use(metricsRouter);

// Root route
server.get("/", (req, res) => {
    res.status(200).json({ message: 'running' })
})

// Test metrics route
server.get('/test-metrics', (req, res) => {
    res.json({ message: 'metrics route reachable' });
});

server.listen(8000, () => {
    console.log('server [STARTED] ~ http://localhost:8000');
    console.log('Routes registered successfully');
})