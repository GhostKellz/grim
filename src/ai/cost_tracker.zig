//! Cost tracking for AI API usage
//! Estimates and tracks costs across different providers

const std = @import("std");

/// Provider cost per 1M tokens
pub const ProviderCost = struct {
    provider_name: []const u8,
    input_cost_per_million: f64, // Cost per 1M input tokens
    output_cost_per_million: f64, // Cost per 1M output tokens

    pub fn anthropic() ProviderCost {
        return .{
            .provider_name = "anthropic",
            .input_cost_per_million = 3.00, // Claude Sonnet 4.5: $3/MTok input
            .output_cost_per_million = 15.00, // $15/MTok output
        };
    }

    pub fn openai() ProviderCost {
        return .{
            .provider_name = "openai",
            .input_cost_per_million = 10.00, // GPT-4 Turbo: $10/MTok input
            .output_cost_per_million = 30.00, // $30/MTok output
        };
    }

    pub fn xai() ProviderCost {
        return .{
            .provider_name = "xai",
            .input_cost_per_million = 5.00, // Grok: $5/MTok input
            .output_cost_per_million = 15.00, // $15/MTok output
        };
    }

    pub fn ollama() ProviderCost {
        return .{
            .provider_name = "ollama",
            .input_cost_per_million = 0.0, // Free (local)
            .output_cost_per_million = 0.0,
        };
    }

    pub fn github_copilot() ProviderCost {
        return .{
            .provider_name = "github_copilot",
            .input_cost_per_million = 0.0, // Subscription-based ($10/month)
            .output_cost_per_million = 0.0,
        };
    }

    pub fn google() ProviderCost {
        return .{
            .provider_name = "google",
            .input_cost_per_million = 2.50, // Gemini: $2.50/MTok input
            .output_cost_per_million = 10.00, // $10/MTok output
        };
    }

    pub fn forProvider(provider: []const u8) ProviderCost {
        if (std.mem.eql(u8, provider, "anthropic")) return anthropic();
        if (std.mem.eql(u8, provider, "openai")) return openai();
        if (std.mem.eql(u8, provider, "xai")) return xai();
        if (std.mem.eql(u8, provider, "ollama")) return ollama();
        if (std.mem.eql(u8, provider, "github_copilot")) return github_copilot();
        if (std.mem.eql(u8, provider, "google")) return google();

        // Default (assume similar to OpenAI)
        return openai();
    }

    pub fn estimateCost(self: ProviderCost, input_tokens: u32, output_tokens: u32) f64 {
        const input_cost = (@as(f64, @floatFromInt(input_tokens)) / 1_000_000.0) * self.input_cost_per_million;
        const output_cost = (@as(f64, @floatFromInt(output_tokens)) / 1_000_000.0) * self.output_cost_per_million;
        return input_cost + output_cost;
    }
};

/// Cost estimate for a request
pub const CostEstimate = struct {
    provider: []const u8,
    input_tokens: u32,
    output_tokens: u32,
    estimated_cost: f64,
    timestamp: i64,

    pub fn format(self: CostEstimate, allocator: std.mem.Allocator) ![]const u8 {
        return try std.fmt.allocPrint(
            allocator,
            "${d:.4} ({s}: {d} in / {d} out tokens)",
            .{ self.estimated_cost, self.provider, self.input_tokens, self.output_tokens },
        );
    }
};

/// Request record for cost tracking
pub const RequestRecord = struct {
    provider: []const u8,
    input_tokens: u32,
    output_tokens: u32,
    cost: f64,
    timestamp: i64,

    allocator: std.mem.Allocator,

    pub fn deinit(self: *RequestRecord) void {
        self.allocator.free(self.provider);
    }
};

/// Cost tracker
pub const CostTracker = struct {
    allocator: std.mem.Allocator,
    records: std.ArrayList(RequestRecord),
    total_cost: f64,
    total_input_tokens: u64,
    total_output_tokens: u64,

    // Per-provider totals
    provider_costs: std.StringHashMap(f64),
    provider_tokens_in: std.StringHashMap(u64),
    provider_tokens_out: std.StringHashMap(u64),

    pub fn init(allocator: std.mem.Allocator) CostTracker {
        return .{
            .allocator = allocator,
            .records = std.ArrayList(RequestRecord).init(allocator),
            .total_cost = 0.0,
            .total_input_tokens = 0,
            .total_output_tokens = 0,
            .provider_costs = std.StringHashMap(f64).init(allocator),
            .provider_tokens_in = std.StringHashMap(u64).init(allocator),
            .provider_tokens_out = std.StringHashMap(u64).init(allocator),
        };
    }

    pub fn deinit(self: *CostTracker) void {
        for (self.records.items) |*record| {
            record.deinit();
        }
        self.records.deinit();
        self.provider_costs.deinit();
        self.provider_tokens_in.deinit();
        self.provider_tokens_out.deinit();
    }

    /// Estimate cost before making request
    pub fn estimateCost(self: *CostTracker, provider: []const u8, input_tokens: u32, output_tokens: u32) CostEstimate {
        _ = self;
        const cost_info = ProviderCost.forProvider(provider);
        const cost = cost_info.estimateCost(input_tokens, output_tokens);

        return .{
            .provider = provider,
            .input_tokens = input_tokens,
            .output_tokens = output_tokens,
            .estimated_cost = cost,
            .timestamp = std.time.timestamp(),
        };
    }

    /// Record actual request
    pub fn recordRequest(self: *CostTracker, provider: []const u8, input_tokens: u32, output_tokens: u32) !void {
        const cost_info = ProviderCost.forProvider(provider);
        const cost = cost_info.estimateCost(input_tokens, output_tokens);

        // Add to records
        const record = RequestRecord{
            .provider = try self.allocator.dupe(u8, provider),
            .input_tokens = input_tokens,
            .output_tokens = output_tokens,
            .cost = cost,
            .timestamp = std.time.timestamp(),
            .allocator = self.allocator,
        };
        try self.records.append(record);

        // Update totals
        self.total_cost += cost;
        self.total_input_tokens += input_tokens;
        self.total_output_tokens += output_tokens;

        // Update per-provider totals
        const provider_key = try self.allocator.dupe(u8, provider);

        if (self.provider_costs.get(provider_key)) |current_cost| {
            try self.provider_costs.put(provider_key, current_cost + cost);
        } else {
            try self.provider_costs.put(provider_key, cost);
        }

        if (self.provider_tokens_in.get(provider_key)) |current| {
            try self.provider_tokens_in.put(provider_key, current + input_tokens);
        } else {
            try self.provider_tokens_in.put(provider_key, input_tokens);
        }

        if (self.provider_tokens_out.get(provider_key)) |current| {
            try self.provider_tokens_out.put(provider_key, current + output_tokens);
        } else {
            try self.provider_tokens_out.put(provider_key, output_tokens);
        }
    }

    /// Get total cost
    pub fn getTotalCost(self: *const CostTracker) f64 {
        return self.total_cost;
    }

    /// Get cost for specific provider
    pub fn getProviderCost(self: *const CostTracker, provider: []const u8) f64 {
        return self.provider_costs.get(provider) orelse 0.0;
    }

    /// Get formatted cost summary
    pub fn getSummary(self: *const CostTracker) ![]const u8 {
        var result = std.ArrayList(u8).init(self.allocator);
        defer result.deinit();

        const writer = result.writer();

        try writer.print("Total Cost: ${d:.4}\n", .{self.total_cost});
        try writer.print("Total Tokens: {d} in / {d} out\n", .{ self.total_input_tokens, self.total_output_tokens });
        try writer.print("Total Requests: {d}\n\n", .{self.records.items.len});

        try writer.writeAll("Per-Provider Breakdown:\n");

        var it = self.provider_costs.iterator();
        while (it.next()) |entry| {
            const provider = entry.key_ptr.*;
            const cost = entry.value_ptr.*;
            const tokens_in = self.provider_tokens_in.get(provider) orelse 0;
            const tokens_out = self.provider_tokens_out.get(provider) orelse 0;

            try writer.print("  {s}: ${d:.4} ({d} in / {d} out)\n", .{ provider, cost, tokens_in, tokens_out });
        }

        return try result.toOwnedSlice();
    }

    /// Clear all records
    pub fn clear(self: *CostTracker) void {
        for (self.records.items) |*record| {
            record.deinit();
        }
        self.records.clearRetainingCapacity();

        self.provider_costs.clearRetainingCapacity();
        self.provider_tokens_in.clearRetainingCapacity();
        self.provider_tokens_out.clearRetainingCapacity();

        self.total_cost = 0.0;
        self.total_input_tokens = 0;
        self.total_output_tokens = 0;
    }

    /// Get recent requests (last N)
    pub fn getRecentRequests(self: *const CostTracker, count: usize) []const RequestRecord {
        const start = if (self.records.items.len > count)
            self.records.items.len - count
        else
            0;

        return self.records.items[start..];
    }

    /// Check if cost exceeds budget
    pub fn exceedsBudget(self: *const CostTracker, budget: f64) bool {
        return self.total_cost > budget;
    }

    /// Get cost warning if approaching budget
    pub fn getCostWarning(self: *const CostTracker, budget: f64) ?[]const u8 {
        const percentage = (self.total_cost / budget) * 100.0;

        if (percentage >= 90.0) {
            return "⚠️  WARNING: 90% of budget used!";
        } else if (percentage >= 75.0) {
            return "⚠️  NOTICE: 75% of budget used";
        } else if (percentage >= 50.0) {
            return "ℹ️  50% of budget used";
        }

        return null;
    }
};

// Tests
test "provider cost calculation" {
    const claude = ProviderCost.anthropic();
    const cost = claude.estimateCost(1000, 1000); // 1k tokens in/out

    try std.testing.expect(cost > 0.0);
    try std.testing.expect(cost < 1.0); // Should be a few cents
}

test "cost tracker" {
    var tracker = CostTracker.init(std.testing.allocator);
    defer tracker.deinit();

    try tracker.recordRequest("anthropic", 1000, 1000);
    try tracker.recordRequest("openai", 500, 500);

    try std.testing.expect(tracker.getTotalCost() > 0.0);
    try std.testing.expectEqual(@as(usize, 2), tracker.records.items.len);
}

test "cost estimate" {
    var tracker = CostTracker.init(std.testing.allocator);
    defer tracker.deinit();

    const estimate = tracker.estimateCost("anthropic", 1000, 1000);
    try std.testing.expect(estimate.estimated_cost > 0.0);
}

test "budget warning" {
    var tracker = CostTracker.init(std.testing.allocator);
    defer tracker.deinit();

    try tracker.recordRequest("anthropic", 100_000, 100_000); // ~$1.80

    const warning = tracker.getCostWarning(2.0);
    try std.testing.expect(warning != null);
}
