// logger.h
// Logging utility for GPU simulator

#pragma once

#include <string>
#include <fstream>
#include <iostream>
#include <sstream>
#include <mutex>
#include <vector>
#include <memory>
#include <chrono>
#include <iomanip>

namespace gpu_simulator {
namespace utils {

// Log levels
enum class LogLevel {
    TRACE   = 0,
    DEBUG   = 1,
    INFO    = 2,
    WARNING = 3,
    ERROR   = 4,
    FATAL   = 5,
    NONE    = 6
};

// Log destination
enum class LogDestination {
    CONSOLE,
    FILE,
    BOTH
};

class Logger {
public:
    // Singleton access
    static Logger& instance() {
        static Logger instance;
        return instance;
    }

    // Initialize logger
    void init(LogDestination dest = LogDestination::CONSOLE, 
              const std::string& filename = "gpu_sim.log", 
              LogLevel level = LogLevel::INFO) {
        std::lock_guard<std::mutex> lock(mutex_);
        destination_ = dest;
        min_level_ = level;
        
        if (dest == LogDestination::FILE || dest == LogDestination::BOTH) {
            file_.open(filename, std::ios::out | std::ios::trunc);
            if (!file_.is_open()) {
                std::cerr << "Failed to open log file: " << filename << std::endl;
                destination_ = LogDestination::CONSOLE;
            }
        }
    }

    // Close logger
    void close() {
        std::lock_guard<std::mutex> lock(mutex_);
        if (file_.is_open()) {
            file_.close();
        }
    }

    // Set log level
    void set_level(LogLevel level) {
        std::lock_guard<std::mutex> lock(mutex_);
        min_level_ = level;
    }

    // Log message with level
    void log(LogLevel level, const std::string& message, 
             const std::string& file = "", int line = 0) {
        std::lock_guard<std::mutex> lock(mutex_);
        
        if (level < min_level_) {
            return;
        }

        // Format the log message
        std::stringstream log_stream;
        
        // Add timestamp
        auto now = std::chrono::system_clock::now();
        auto time = std::chrono::system_clock::to_time_t(now);
        auto ms = std::chrono::duration_cast<std::chrono::milliseconds>(
            now.time_since_epoch()) % 1000;
            
        log_stream << std::put_time(std::localtime(&time), "%Y-%m-%d %H:%M:%S")
                   << '.' << std::setfill('0') << std::setw(3) << ms.count()
                   << " [" << level_to_string(level) << "] ";
                   
        // Add source info if available
        if (!file.empty()) {
            log_stream << file << ":" << line << " ";
        }
        
        // Add message
        log_stream << message;
        
        // Output to appropriate destination
        if (destination_ == LogDestination::CONSOLE || 
            destination_ == LogDestination::BOTH) {
            std::cout << log_stream.str() << std::endl;
        }
        
        if ((destination_ == LogDestination::FILE || 
             destination_ == LogDestination::BOTH) && file_.is_open()) {
            file_ << log_stream.str() << std::endl;
            file_.flush();
        }
    }

    // Helper methods for different log levels
    void trace(const std::string& message, const std::string& file = "", int line = 0) {
        log(LogLevel::TRACE, message, file, line);
    }
    
    void debug(const std::string& message, const std::string& file = "", int line = 0) {
        log(LogLevel::DEBUG, message, file, line);
    }
    
    void info(const std::string& message, const std::string& file = "", int line = 0) {
        log(LogLevel::INFO, message, file, line);
    }
    
    void warning(const std::string& message, const std::string& file = "", int line = 0) {
        log(LogLevel::WARNING, message, file, line);
    }
    
    void error(const std::string& message, const std::string& file = "", int line = 0) {
        log(LogLevel::ERROR, message, file, line);
    }
    
    void fatal(const std::string& message, const std::string& file = "", int line = 0) {
        log(LogLevel::FATAL, message, file, line);
    }

private:
    // Private constructor for singleton
    Logger() : min_level_(LogLevel::INFO), destination_(LogDestination::CONSOLE) {}
    ~Logger() { close(); }

    // Delete copy constructor and assignment
    Logger(const Logger&) = delete;
    Logger& operator=(const Logger&) = delete;

    // Convert log level to string
    std::string level_to_string(LogLevel level) {
        switch (level) {
            case LogLevel::TRACE:   return "TRACE";
            case LogLevel::DEBUG:   return "DEBUG";
            case LogLevel::INFO:    return "INFO";
            case LogLevel::WARNING: return "WARN";
            case LogLevel::ERROR:   return "ERROR";
            case LogLevel::FATAL:   return "FATAL";
            default:                return "UNKNOWN";
        }
    }

    LogLevel min_level_;
    LogDestination destination_;
    std::ofstream file_;
    std::mutex mutex_;
};

// Convenience macros
#define LOG_TRACE(msg) gpu_simulator::utils::Logger::instance().trace(msg, __FILE__, __LINE__)
#define LOG_DEBUG(msg) gpu_simulator::utils::Logger::instance().debug(msg, __FILE__, __LINE__)
#define LOG_INFO(msg)  gpu_simulator::utils::Logger::instance().info(msg, __FILE__, __LINE__)
#define LOG_WARN(msg)  gpu_simulator::utils::Logger::instance().warning(msg, __FILE__, __LINE__)
#define LOG_ERROR(msg) gpu_simulator::utils::Logger::instance().error(msg, __FILE__, __LINE__)
#define LOG_FATAL(msg) gpu_simulator::utils::Logger::instance().fatal(msg, __FILE__, __LINE__)

} // namespace utils
} // namespace gpu_simulator