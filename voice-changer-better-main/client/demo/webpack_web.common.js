const path = require("path");
const fs = require("fs");
const HtmlWebpackPlugin = require("html-webpack-plugin");
const CopyPlugin = require("copy-webpack-plugin");
const webpack = require("webpack");

// Helper function to check if file exists
function fileExists(filePath) {
    try {
        return fs.existsSync(path.resolve(__dirname, filePath));
    } catch (e) {
        return false;
    }
}

// Build plugins array dynamically
const plugins = [
    new webpack.ProvidePlugin({
        Buffer: ["buffer", "Buffer"],
    }),
    new HtmlWebpackPlugin({
        template: path.resolve(__dirname, "public/index.html"),
        filename: "./index.html",
    }),
    new CopyPlugin({
        patterns: [{ from: "public/assets", to: "assets" }],
    }),
    new CopyPlugin({
        patterns: [{ from: "public/favicon.ico", to: "favicon.ico" }],
    }),
];

// Add optional VC files only if they exist
const optionalFiles = [
    { from: "./node_modules/@dannadori/voice-changer-js/dist/ort-wasm-simd.wasm", to: "ort-wasm-simd.wasm" },
    { from: "./node_modules/@dannadori/voice-changer-js/dist/tfjs-backend-wasm-simd.wasm", to: "tfjs-backend-wasm-simd.wasm" },
    { from: "./node_modules/@dannadori/voice-changer-js/dist/process.js", to: "process.js" },
    { from: "public/models/rvcv2_exp_v2_32k_f0_24000.bin", to: "models/rvcv2_exp_v2_32k_f0_24000.bin" },
    { from: "public/models/rvcv2_vctk_v2_16k_f0_24000.bin", to: "models/rvcv2_vctk_v2_16k_f0_24000.bin" },
];

optionalFiles.forEach(({ from, to }) => {
    if (fileExists(from)) {
        plugins.push(
            new CopyPlugin({
                patterns: [{ from, to }],
            })
        );
    }
});

module.exports = {
    mode: "production",
    entry: "./src/000_index.tsx",
    resolve: {
        extensions: [".ts", ".tsx", ".js"],
        fallback: {
            buffer: require.resolve("buffer/"),
        },
    },
    module: {
        rules: [
            {
                test: [/\.ts$/, /\.tsx$/],
                use: [
                    {
                        loader: "babel-loader",
                        options: {
                            presets: ["@babel/preset-env", "@babel/preset-react", "@babel/preset-typescript"],
                            plugins: ["@babel/plugin-transform-runtime"],
                        },
                    },
                ],
            },
            {
                test: /\.html$/,
                loader: "html-loader",
            },
            {
                test: /\.css$/,
                use: ["style-loader", { loader: "css-loader", options: { importLoaders: 1 } }, "postcss-loader"],
            },
            { test: /\.json$/, type: "asset/inline" },
            { test: /\.svg$/, type: "asset/resource" },
        ],
    },
    output: {
        filename: "index.js",
        path: path.resolve(__dirname, "dist_web"),
    },
    plugins: plugins,
};
