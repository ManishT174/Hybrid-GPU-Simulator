// utils.h
// Utility functions for GPU simulator

#pragma once

#include <string>
#include <vector>
#include <sstream>
#include <iomanip>
#include <algorithm>
#include <functional>
#include <cstdint>
#include <chrono>
#include <random>

namespace gpu_simulator {
namespace utils {

// String manipulation utilities
class StringUtils {
public:
    // Trim whitespace from left side
    static std::string ltrim(const std::string& s) {
        std::string str = s;
        str.erase(str.begin(), std::find_if(str.begin(), str.end(), [](unsigned char ch) {
            return !std::isspace(ch);
        }));
        return str;
    }

    // Trim whitespace from right side
    static std::string rtrim(const std::string& s) {
        std::string str = s;
        str.erase(std::find_if(str.rbegin(), str.rend(), [](unsigned char ch) {
            return !std::isspace(ch);
        }).base(), str.end());
        return str;
    }

    // Trim whitespace from both sides
    static std::string trim(const std::string& s) {
        return ltrim(rtrim(s));
    }

    // Split string by delimiter
    static std::vector<std::string> split(const std::string& s, char delimiter) {
        std::vector<std::string> tokens;
        std::string token;
        std::istringstream tokenStream(s);
        while (std::getline(tokenStream, token, delimiter)) {
            tokens.push_back(token);
        }
        return tokens;
    }

    // Join vector of strings with delimiter
    static std::string join(const std::vector<std::string>& strings, const std::string& delimiter) {
        std::string result;
        for (size_t i = 0; i < strings.size(); ++i) {
            result += strings[i];
            if (i < strings.size() - 1) {
                result += delimiter;
            }
        }
        return result;
    }

    // Check if string starts with prefix
    static bool starts_with(const std::string& s, const std::string& prefix) {
        return s.size() >= prefix.size() && s.compare(0, prefix.size(), prefix) == 0;
    }

    // Check if string ends with suffix
    static bool ends_with(const std::string& s, const std::string& suffix) {
        return s.size() >= suffix.size() && 
               s.compare(s.size() - suffix.size(), suffix.size(), suffix) == 0;
    }

    // Convert to uppercase
    static std::string to_upper(const std::string& s) {
        std::string result = s;
        std::transform(result.begin(), result.end(), result.begin(), 
                      [](unsigned char c) { return std::toupper(c); });
        return result;
    }

    // Convert to lowercase
    static std::string to_lower(const std::string& s) {
        std::string result = s;
        std::transform(result.begin(), result.end(), result.begin(), 
                      [](unsigned char c) { return std::tolower(c); });
        return result;
    }

    // Format integer to hex string
    static std::string to_hex(uint32_t value, bool prefix = true, int width = 8) {
        std::stringstream ss;
        if (prefix) {
            ss << "0x";
        }
        ss << std::hex << std::setw(width) << std::setfill('0') << value;
        return ss.str();
    }

    // Format binary string
    static std::string to_binary(uint32_t value, bool prefix = true, int width = 32) {
        std::stringstream ss;
        if (prefix) {
            ss << "0b";
        }
        for (int i = width - 1; i >= 0; --i) {
            ss << ((value >> i) & 1);
        }
        return ss.str();
    }
};

// File utilities
class FileUtils {
public:
    // Check if file exists
    static bool file_exists(const std::string& filename) {
        std::ifstream f(filename.c_str());
        return f.good();
    }

    // Read entire file to string
    static std::string read_file(const std::string& filename) {
        std::ifstream file(filename);
        if (!file.is_open()) {
            throw std::runtime_error("Could not open file: " + filename);
        }
        
        return std::string(std::istreambuf_iterator<char>(file),
                          std::istreambuf_iterator<char>());
    }

    // Read file lines to vector
    static std::vector<std::string> read_lines(const std::string& filename) {
        std::ifstream file(filename);
        if (!file.is_open()) {
            throw std::runtime_error("Could not open file: " + filename);
        }
        
        std::vector<std::string> lines;
        std::string line;
        while (std::getline(file, line)) {
            lines.push_back(line);
        }
        
        return lines;
    }

    // Write string to file
    static void write_file(const std::string& filename, const std::string& content) {
        std::ofstream file(filename);
        if (!file.is_open()) {
            throw std::runtime_error("Could not open file for writing: " + filename);
        }
        
        file << content;
    }

    // Append string to file
    static void append_file(const std::string& filename, const std::string& content) {
        std::ofstream file(filename, std::ios_base::app);
        if (!file.is_open()) {
            throw std::runtime_error("Could not open file for appending: " + filename);
        }
        
        file << content;
    }

    // Get file size
    static size_t file_size(const std::string& filename) {
        std::ifstream file(filename, std::ios::binary | std::ios::ate);
        if (!file.is_open()) {
            throw std::runtime_error("Could not open file: " + filename);
        }
        
        return static_cast<size_t>(file.tellg());
    }

    // Get file extension
    static std::string get_extension(const std::string& filename) {
        size_t pos = filename.find_last_of('.');
        if (pos == std::string::npos) {
            return "";
        }
        
        return filename.substr(pos + 1);
    }
};

// Random number generation
class Random {
public:
    // Initialize with random seed
    Random() : engine_(std::random_device()()) {}
    
    // Initialize with specific seed
    Random(uint32_t seed) : engine_(seed) {}

    // Get random integer in range [min, max]
    int get_int(int min, int max) {
        std::uniform_int_distribution<int> dist(min, max);
        return dist(engine_);
    }

    // Get random float in range [min, max)
    float get_float(float min, float max) {
        std::uniform_real_distribution<float> dist(min, max);
        return dist(engine_);
    }

    // Get random double in range [min, max)
    double get_double(double min, double max) {
        std::uniform_real_distribution<double> dist(min, max);
        return dist(engine_);
    }

    // Get random boolean with given probability
    bool get_bool(double true_probability = 0.5) {
        std::bernoulli_distribution dist(true_probability);
        return dist(engine_);
    }

private:
    std::mt19937 engine_;
};

// Timing utilities
class Timer {
public:
    // Start timer
    void start() {
        start_time_ = std::chrono::high_resolution_clock::now();
        running_ = true;
    }

    // Stop timer
    void stop() {
        end_time_ = std::chrono::high_resolution_clock::now();
        running_ = false;
    }

    // Reset timer
    void reset() {
        start_time_ = std::chrono::high_resolution_clock::now();
        end_time_ = start_time_;
    }

    // Get elapsed time in milliseconds
    double elapsed_ms() {
        auto end = running_ ? 
            std::chrono::high_resolution_clock::now() : end_time_;
            
        return std::chrono::duration<double, std::milli>(
            end - start_time_).count();
    }

    // Get elapsed time in seconds
    double elapsed_sec() {
        return elapsed_ms() / 1000.0;
    }

private:
    std::chrono::high_resolution_clock::time_point start_time_;
    std::chrono::high_resolution_clock::time_point end_time_;
    bool running_ = false;
};

} // namespace utils
} // namespace gpu_simulator